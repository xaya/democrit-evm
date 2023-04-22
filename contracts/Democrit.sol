// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./LimitSelling.sol";
import "./VaultManager.sol";

/**
 * @dev This is the main contract for the Democrit exchange.  Most of the
 * functionality is inherited from parent contracts already and just
 * consolidated here.
 */
contract Democrit is LimitSelling
{

  constructor (VaultManager v)
    LimitSelling(v)
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

}
