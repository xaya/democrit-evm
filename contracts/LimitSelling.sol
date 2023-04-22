// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./VaultManager.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @dev This contract implements limit sell orders as part of Democrit
 * (the "easy part").  Limit buy orders together with liquidity pools
 * are missing, and will be added in a subcontract.
 */
contract LimitSelling is Context
{

  /** @dev The VaultManager instance owned by this contract.  */
  VaultManager public immutable vm;

  /**
   * @dev The WCHI contract used for trading.  This matches the WCHI
   * in the VaultManager, but is replicated here to give easy access.
   */
  IERC20Metadata public immutable wchi;


  /**
   * @dev The data stored on chain for an active limit sell order.
   */
  struct SellOrder
  {

    /**
     * @dev The vault holding the assets to be sold.  This implies
     * the asset, remaining quantity, and owner (founder of the vault).
     */
    uint vaultId;

    /**
     * @dev The address which owned the vault's founder name at creation
     * time.  The order is only valid to take when it still is the owner,
     * to prevent potential attacks with creating orders and
     * transferring/selling the name.
     */
    address creator;

    /**
     * @dev The amount in WCHI sats required to buy out the entire vault's
     * remaining balance.  This implies the limit price by proportion.
     */
    uint totalSats;

  }

  /**
   * @dev Complete data for a sell order, including the "implied"
   * bits of information.  This is not stored anywhere, but returned
   * from helper functions in memory.
   */
  struct CompleteSellOrder
  {

    /** @dev The ID of the order.  */
    uint orderId;

    /** @dev The vault ID associated to it.  */
    uint vaultId;

    /** @dev The owner address at creation time.  */
    address creator;

    /** @dev The seller account.  */
    string seller;

    /** @dev The asset being sold.  */
    string asset;

    /** @dev The remaining amount of asset available.  */
    uint remainingAmount;

    /** @dev The total in WCHI sats asked for the remainingAmount.  */
    uint totalSats;

  }

  /**
   * @dev The next ID given to a limit order.  The same sequence of IDs is
   * applied to limit sell and future limit buy orders.
   */
  uint public nextOrderId;

  /** @dev All active sell orders by ID.  */
  mapping (uint => SellOrder) private sellOrders;

  /** @dev Emitted when a new sell order is created.  */
  event SellOrderCreated (uint orderId, uint vaultId, address creator,
                          string seller, string asset,
                          uint amount, uint totalSats);
  /**
   * @dev Emitted when an existing sell order is updated
   * (i.e. partially taken).
   */
  event SellOrderUpdated (uint orderId, uint amount, uint totalSats);
  /**
   * @dev Emitted when a sell order is removed, either by being cancelled
   * or taken entirely.
   */
  event SellOrderRemoved (uint orderId);

  /**
   * @dev Emitted when a trade happens.  This is also emitted from the
   * subcontract doing limit buy orders.
   */
  event Trade (string asset, uint amount, uint sats,
               string seller, string buyer);

  constructor (VaultManager v)
  {
    vm = v;
    wchi = vm.wchi ();

    /* We start with ID 1, so that an ID being zero can be taken to mean
       that data does not exist.  */
    nextOrderId = 1;
  }

  /**
   * @dev Returns the amount of WCHI sats required to pay for
   * the given amount of assets from an order, based on the total remaining
   * amount and sats price for all of it.  This is a utility method which
   * can also be applied for limit buy orders.
   *
   * The amount will be linearly interpolated (i.e. just proportional),
   * rounding up to the next full sat.
   */
  function getSatsForPurchase (uint remainingAmount, uint totalSats,
                               uint amountBought) public pure returns (uint)
  {
    require (remainingAmount > 0, "expected non-zero remaining amount");
    require (amountBought > 0, "amount bought must be non-zero");
    require (amountBought <= remainingAmount, "amount exceeds remaining");

    /* If purchasing all, then the price will be just the asked total.  */
    if (amountBought == remainingAmount)
      return totalSats;

    /* Otherwise, the price will be proportional to the amount bought,
       rounded up to the next sat.  Note that if the product overflows,
       this will revert (instead of silently proceed) due to Solidity 0.8
       "safe math" semantics.  But totalSats is in a safe range anyway,
       as it will be verified against the user's WCHI balance, and
       if the amount would be out of range, then the vault would not exist
       and thus the trade should not proceed anyway.  */
    return (amountBought * totalSats + remainingAmount - 1) / remainingAmount;
  }

  /**
   * @dev Returns full data for a given sell order by ID, including the
   * fields taken from the vaults storage.
   */
  function getSellOrder (uint orderId)
      public view returns (CompleteSellOrder memory)
  {
    SellOrder storage data = sellOrders[orderId];
    uint vaultId = data.vaultId;
    if (vaultId == 0)
      {
        CompleteSellOrder memory nullOrder;
        return nullOrder;
      }

    VaultManager.VaultData memory vault = vm.getVault (vaultId);
    /* When the vault associated to an order is emptied, the order
       is removed as well.  So if the order exists, the vault must
       exist (with non-zero balance), too.  */
    assert (vault.balance > 0);

    return CompleteSellOrder ({
      orderId: orderId,
      vaultId: vaultId,
      creator: data.creator,
      totalSats: data.totalSats,
      seller: vault.founder,
      asset: vault.asset,
      remainingAmount: vault.balance
    });
  }

  /**
   * @dev Creates a new limit sell order with the given specifics.  Returns
   * the order ID of the new order.
   */
  function createSellOrder (string memory seller, string memory asset,
                            uint amount, uint totalSats)
      public returns (uint)
  {
    require (amount > 0, "non-zero amount required");
    require (vm.hasAccountPermission (_msgSender (), seller),
             "no permission to act on behalf of this account");

    uint vaultId = vm.createVault (seller, asset, amount);
    assert (vaultId > 0);
    uint orderId = nextOrderId++;
    address creator = vm.getAccountAddress (seller);

    sellOrders[orderId] = SellOrder ({
      vaultId: vaultId,
      creator: creator,
      totalSats: totalSats
    });
    emit SellOrderCreated (orderId, vaultId, creator, seller,
                           asset, amount, totalSats);

    return orderId;
  }

  /**
   * @dev Cancels an existing limit sell order, refunding the vault's
   * remaining asset balance to the owner.
   */
  function cancelSellOrder (uint orderId) public
  {
    CompleteSellOrder memory data = getSellOrder (orderId);
    require (data.orderId == orderId, "order does not exist");
    require (vm.hasAccountPermission (_msgSender (), data.seller),
             "no permission to act on behalf of the seller account");

    vm.sendFromVault (data.vaultId, data.seller, data.remainingAmount);
    delete sellOrders[orderId];
    emit SellOrderRemoved (orderId);
  }

  /**
   * @dev Arguments required for accepting a sell order (i.e. "market buy").
   * We put them into a struct, so that we can easily provide a function
   * to accept a batch of orders (when that is necessary to fill the desired
   * buy on the front-end side).
   */
  struct AcceptedSellOrder
  {

    /** The order ID being accepted.  */
    uint orderId;

    /** The amount of asset being bought.  */
    uint amountBought;

    /** The buyer's account name to send assets to.  */
    string buyer;

    /** The checkpoint against which the vault was verified in the GSP.  */
    bytes32 checkpoint;

    /* Note that the limit price of orders is immutable once the order
       is created (it may only go down marginally due to rounding up the
       prices paid by previous takers).  Thus there is no need to specify
       the expected price when taking an order.

       Even reorgs that would create a differing order are not possible,
       since the checkpoint protects against them.  */

  }

  /**
   * @dev Accepts a limit sell order, buying all or part of the offered
   * asset.  The payment is taken in WCHI from the _msgSender() and
   * forwarded to the current owner of the seller account name.
   */
  function acceptSellOrder (AcceptedSellOrder calldata args) public
  {
    CompleteSellOrder memory data = getSellOrder (args.orderId);
    require (data.orderId > 0, "order does not exist");
    require (vm.isCheckpoint (args.checkpoint), "vault checkpoint is invalid");
    /* Calculating the purchase amount of sats checks for the amount bought
       being non-zero and not exceeding the available amount already, so there
       is no need to explicitly check those here.  */
    uint sats = getSatsForPurchase (data.remainingAmount, data.totalSats,
                                    args.amountBought);

    address sellerAddress = vm.getAccountAddress (data.seller);
    require (sellerAddress == data.creator, "seller name has been transferred");

    require (wchi.transferFrom (_msgSender (), sellerAddress, sats),
             "WCHI transfer failed");
    vm.sendFromVault (data.vaultId, args.buyer, args.amountBought);

    emit Trade (data.asset, args.amountBought, sats, data.seller, args.buyer);
    if (args.amountBought == data.remainingAmount)
      {
        delete sellOrders[data.orderId];
        emit SellOrderRemoved (data.orderId);
      }
    else
      {
        uint newRemaining = data.remainingAmount - args.amountBought;
        assert (newRemaining > 0);
        uint newSats = data.totalSats - sats;

        sellOrders[data.orderId].totalSats = newSats;
        emit SellOrderUpdated (data.orderId, newRemaining, newSats);
      }
  }

  /**
   * @dev Accepts a batch of limit sell orders as per acceptSellOrder.  This
   * allows to fill a range of orders in a single transaction, as may be
   * required to fill a particular "market buy".
   */
  function acceptSellOrders (AcceptedSellOrder[] calldata orders) public
  {
    for (uint i = 0; i < orders.length; ++i)
      acceptSellOrder (orders[i]);
  }

}
