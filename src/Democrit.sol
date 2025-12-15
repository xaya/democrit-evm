// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./LimitBuying.sol";
import "./VaultManager.sol";

/**
 * @dev This is the main contract for the Democrit exchange.  Most of the
 * functionality is inherited from parent contracts already and just
 * consolidated here.
 *
 * The functions added explicitly in this contract are helpers for
 * retrieving some data, which e.g. frontends can utilise.  They are not
 * used in consensus-critical state changes.
 */
contract Democrit is LimitBuying
{

  constructor (VaultManager v)
    LimitBuying(v)
  {}

  /**
   * @dev The current status of a sell order.  This has some extra bits
   * of information (like whether or not the order even exists, and
   * is valid) in addition to the basic order details.
   */
  struct SellOrderStatus
  {

    /** @dev The order data itself.  */
    CompleteSellOrder order;

    /** @dev Whether or not the order exists.  */
    bool exists;

    /**
     * @dev Whether or not it is valid, e.g. the creator address matches
     * the current account owner.
     */
    bool valid;

  }

  /**
   * @dev Given an array of order IDs for sell orders, this function
   * checks each one of them to see if they are currently valid (e.g.
   * the creator address matches the current owner of the seller account),
   * exist, and returns all the data for it.  This is meant to be used
   * by a frontend to query the state of orders in batch before displaying
   * and using them.
   */
  function checkSellOrders (uint[] calldata orderIds)
      public view returns (SellOrderStatus[] memory res)
  {
    res = new SellOrderStatus[] (orderIds.length);
    for (uint i = 0; i < orderIds.length; ++i)
      {
        res[i].order = getSellOrder (orderIds[i]);
        res[i].exists = (res[i].order.orderId == orderIds[i]);
        if (res[i].exists)
          {
            address owner = vm.getAccountAddress (res[i].order.seller);
            res[i].valid = (res[i].order.creator == owner);
          }
      }
  }

  /**
   * @dev The current status of a buy order.  This has some extra information
   * added, based on linking it to other state like the WCHI balance of the
   * buyer or the state of the trading pool.
   */
  struct BuyOrderStatus
  {

    /** @dev The order data itself.  */
    CompleteBuyOrder order;

    /** @dev Whether or not the order exists.  */
    bool exists;

    /**
     * @dev Whether or not the order is valid, e.g. the creator address
     * matches the current account owner.
     */
    bool valid;

    /** @dev The current approved WCHI balance of the buyer.  */
    uint availableSats;

    /**
     * @dev The maximum amount of asset that can be bought, taking the
     * buyer's available WCHI balance and the pool balance into account.
     * Note that this only applies if this order alone is taken!  If multiple
     * orders are taken as a batch that use the same pool or are from the same
     * buyer, then the available amount may be lower.
     */
    uint maxBuy;

  }

  /**
   * @dev Computes the total cost in WCHI sats that a given buy, taking
   * pool fees into account, will be.
   */
  function getTotalBuyCost (uint remainingAmount, uint totalSats, uint64 relFee,
                            uint amountBought)
      public view returns (uint)
  {
    if (amountBought == 0)
      return 0;

    uint sats = getSatsForPurchase (remainingAmount, totalSats, amountBought);
    uint fee = getPoolFee (relFee, sats);
    return sats + fee;
  }

  /**
   * @dev Computes the maximum amount of asset that can be bought with
   * given WCHI, taking the pool fee into account as well.
   */
  function getMaxBuy (uint remainingAmount, uint totalSats, uint64 relFee,
                      uint availableSats)
      public view returns (uint)
  {
    /* Assuming exact math, the total cost for a given buy x is:

        cost = (x * totalSats / remainingAmount) * (1 + relFee / denom)

       Solving this for x yields:

        x = (remainingAmount / totalSats) * cost / (1 + relFee / denom)
          = (remainingAmount * cost * denom) / (totalSats * (denom + relFee))

       We use this formula to calculate the max buy first, plus add one unit to
       overestimate the real value for sure (since also the fee + cost
       calculations are rounding up).  Then we use a binary search between
       zero and that value to find the real maximal value.
    */

    if (totalSats == 0)
      return remainingAmount;
    if (getTotalBuyCost (remainingAmount, totalSats, relFee, remainingAmount)
          <= availableSats)
      return remainingAmount;

    uint denom = config.feeDenominator ();
    uint maxBuy = (remainingAmount * availableSats * denom)
                    / (totalSats * (denom + uint256 (relFee))) + 1;
    /* Note that here, maxBuy may actually be larger than remainingAmount
       due to the "+1".  But we verify at the end that the value returned
       from the function is below remainingAmount.  */

    assert (getTotalBuyCost (remainingAmount, totalSats, relFee, maxBuy)
              > availableSats);

    uint upper = maxBuy;
    uint lower = 0;

    while (upper > lower + 1)
      {
        uint mid = (upper + lower) / 2;
        uint cost = getTotalBuyCost (remainingAmount, totalSats, relFee, mid);
        if (cost > availableSats)
          upper = mid;
        else
          lower = mid;
      }

    assert (upper == lower + 1);
    assert (lower < remainingAmount);

    return lower;
  }

  /**
   * @dev Given an array of order IDs for buy orders, this function retrieves
   * the relevant data and also verifies some extra things, including computing
   * the maximum amount of asset that can be bought based on the buyer's
   * current WCHI balance and the pool's available balance.
   */
  function checkBuyOrders (uint[] calldata orderIds)
      public view returns (BuyOrderStatus[] memory res)
  {
    res = new BuyOrderStatus[] (orderIds.length);
    for (uint i = 0; i < orderIds.length; ++i)
      {
        res[i].order = getBuyOrder (orderIds[i]);
        res[i].exists = (res[i].order.orderId == orderIds[i]);
        if (!res[i].exists)
          continue;

        address owner = vm.getAccountAddress (res[i].order.buyer);
        res[i].valid = (res[i].order.creator == owner);

        uint balance = wchi.balanceOf (owner);
        uint approved = wchi.allowance (owner, address (this));
        if (balance > approved)
          balance = approved;
        res[i].availableSats = balance;

        uint maxBuy = getMaxBuy (res[i].order.remainingAmount,
                                 res[i].order.totalSats,
                                 res[i].order.poolData.relFee,
                                 balance);
        if (maxBuy > res[i].order.poolData.amount)
          maxBuy = res[i].order.poolData.amount;
        res[i].maxBuy = maxBuy;
      }
  }

}
