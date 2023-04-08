// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./IDemocritConfig.sol";
import "./LimitSelling.sol";
import "./VaultManager.sol";

/**
 * @dev This contract adds support for limit buy orders, together with the
 * trading pools needed for it, to Democrit.
 */
contract LimitBuying is LimitSelling
{

  /**
   * @dev The Democrit config.  This matches the config of the associated
   * VaultManager, but is duplicated here for easier access.
   */
  IDemocritConfig public immutable config;

  /* ************************************************************************ */

  /**
   * @dev The data stored for a trading pool.
   *
   * Note that this is just the "extra data" required in addition to the
   * base data in the associated vault.  The vault ID is used as key in the
   * mapping of existing pools.
   */
  struct Pool
  {

    /**
     * @dev Set to true for pools that exist.  Since the relFee might be zero
     * for an existing pool, we need this to distinguish pools from non-existing
     * data in the mapping.
     */
    bool exists;

    /**
     * @dev The relative fee charged by this pool, in a fraction relative
     * to the config's feeDenominator.
     */
    uint64 relFee;

    /* The asset inside a pool, the remaining quantity and the owner account
       of the pool are implied by the associated vault.  */

  }

  /**
   * @dev Existing trading pools.  They are indexed by a subset of existing
   * vault IDs.  A pool exists for each vault that has an index here.
   */
  mapping (uint => Pool) private pools;

  /** @dev Emitted when a pool is created.  */
  event PoolCreated (uint vaultId, string operator, string endpoint,
                     string asset, uint amount, uint64 relFee);

  /** @dev Emitted when a pool has the balance updated.  */
  event PoolUpdated (uint vaultId, uint newAmount);

  /** @dev Emitted when a pool is emptied / removed.  */
  event PoolRemoved (uint vaultId);

  /** @dev All vaults that are sell deposits.  No extra data is needed.  */
  mapping (uint => bool) private sellDeposits;

  /** @dev Emitted when a sell deposit is created.  */
  event SellDepositCreated (uint vaultId, string owner,
                            string asset, uint amount);

  /** @dev Emitted when a sell deposit changes balance.  */
  event SellDepositUpdated (uint vaultId, uint newAmount);

  /** @dev Emitted when a sell deposit is removed.  */
  event SellDepositRemoved (uint vaultId);

  /**
   * @dev The data stored for an active limit buy order.
   */
  struct BuyOrder
  {

    /**
     * @dev The trading pool to be used.  If the pool becomes emptied and
     * removed, the order itself will be seen as void (even if this struct
     * is still in storage).  If the pool's balance drops below remainingAmount
     * but is non-zero, then up to this amount can be bought.
     */
    uint poolId;

    /**
     * @dev The address which owned the buyer account name when the order
     * was created.  It can only be taken if it still owns the account.
     */
    address creator;

    /** @dev The account name owning this order.  */
    string buyer;

    /** @dev The amount of asset that is still to be bought.  */
    uint remainingAmount;

    /** @dev The total in WCHI sats offered for the remainingAmount.  */
    uint totalSats;

    /* The asset being bought is implied by the trading pool used.  */

  }

  /** @dev Existing buy orders by ID.  */
  mapping (uint => BuyOrder) private buyOrders;

  /** @dev Emitted when a buy order is created.  */
  event BuyOrderCreated (uint orderId, uint poolId, address creator,
                         string buyer, string asset,
                         uint amount, uint totalSats);
  /** @dev Emitted when a buy order is updated.  */
  event BuyOrderUpdated (uint orderId, uint amount, uint totalSats);
  /** @dev Emitted when a buy order is removed.  */
  event BuyOrderRemoved (uint orderId);

  /* ************************************************************************ */

  constructor (VaultManager v)
    LimitSelling(v)
  {
    config = v.config ();
  }

  /* ************************************************************************ */

  /**
   * @dev Computes the fee in sats to be paid to a pool, based on its
   * configured relative fee, for processing a trade of the given sats.
   */
  function getPoolFee (uint64 relFee, uint totalSats) public view returns (uint)
  {
    /* We round the fee up to the next sat.  */
    uint denom = config.feeDenominator ();
    return (totalSats * uint256 (relFee) + denom - 1) / denom;
  }

  /**
   * @dev Complete data associated to a trading pool, including the
   * fields implied by the vault.  This struct is not stored on chain but
   * used to return data in memory.
   */
  struct CompletePool
  {

    /** @dev The pool's and associated vault's ID.  */
    uint vaultId;

    /** @dev The operator of the pool.  */
    string operator;

    /** @dev The asset inside the pool.  */
    string asset;

    /** @dev Amount of asset remaining in the pool.  */
    uint amount;

    /** @dev Relative fee charged by the pool.  */
    uint64 relFee;

  }

  /**
   * @dev Returns the full data associated to a given trading pool.
   * Returns a zero struct (in particular, vaultId being zero) if no such
   * pool exists.
   */
  function getPool (uint vaultId)
      public view returns (CompletePool memory)
  {
    Pool storage data = pools[vaultId];
    if (!data.exists)
      {
        CompletePool memory nullPool;
        return nullPool;
      }

    VaultManager.VaultData memory vault = vm.getVault (vaultId);
    /* When the vault is emptied, the pool is removed.  So since the pool
       exists, the vault must exist and be non-empty as well.  */
    assert (vault.balance > 0);

    return CompletePool ({
      vaultId: vaultId,
      operator: vault.founder,
      asset: vault.asset,
      amount: vault.balance,
      relFee: data.relFee
    });
  }

  /**
   * @dev Vaults the given funds into a freshly created trading pool.
   * The endpoint is an (optional) string specifying how the pool can be
   * contacted with requests to verify vaults; it will be emitted in the
   * event data, so can be retrieved from an indexer like The Graph
   * by the frontend.
   */
  function createPool (string memory operator, string memory endpoint,
                       string memory asset,
                       uint amount, uint64 relFee)
      public returns (uint)
  {
    require (amount > 0, "non-zero amount required");
    require (relFee <= config.maxRelPoolFee (), "fee too high");
    require (vm.hasAccountPermission (_msgSender (), operator),
             "no permission to act on behalf of this account");

    uint vaultId = vm.createVault (operator, asset, amount);
    assert (vaultId > 0);

    pools[vaultId] = Pool ({
      exists: true,
      relFee: relFee
    });
    emit PoolCreated (vaultId, operator, endpoint, asset, amount, relFee);

    return vaultId;
  }

  /**
   * @dev Cancels an existing trading pool, refunding all remaining asset
   * in the vault to the operator.  This will of course invalidate all
   * open buy orders based on this pool.
   */
  function cancelPool (uint vaultId) public
  {
    CompletePool memory data = getPool (vaultId);
    require (data.vaultId == vaultId, "trading pool does not exist");
    require (vm.hasAccountPermission (_msgSender (), data.operator),
             "no permission to act on behalf of the operator account");

    vm.sendFromVault (data.vaultId, data.operator, data.amount);
    delete pools[vaultId];
    emit PoolRemoved (vaultId);
  }

  /* ************************************************************************ */

  /**
   * @dev Complete data for a sell deposit, as it is returned in memory
   * when querying the contract.
   */
  struct CompleteSellDeposit
  {

    /** @dev The vault's associated ID.  */
    uint vaultId;

    /** @dev The owner of the deposit.  */
    string owner;

    /** @dev The asset inside the vault.  */
    string asset;

    /** @dev Amount of asset remaining in the vault.  */
    uint amount;

  }

  /**
   * @dev Returns the data for a sell deposit.  They are identified and
   * queried by vault ID.  If the vault does not exist or is not a sell
   * deposit, then a null struct will be returned.
   */
  function getSellDeposit (uint vaultId)
      public view returns (CompleteSellDeposit memory)
  {
    if (!sellDeposits[vaultId])
      {
        CompleteSellDeposit memory nullDeposit;
        return nullDeposit;
      }

    VaultManager.VaultData memory vault = vm.getVault (vaultId);
    assert (vault.balance > 0);

    return CompleteSellDeposit ({
      vaultId: vaultId,
      owner: vault.founder,
      asset: vault.asset,
      amount: vault.balance
    });
  }

  /**
   * @dev Vaults the given funds into a freshly created sell deposit,
   * that the user can then use to accept a buy order (or just keep
   * available / redeem later).
   */
  function createSellDeposit (string memory owner,
                              string memory asset, uint amount)
      public returns (uint)
  {
    require (amount > 0, "non-zero amount required");
    require (vm.hasAccountPermission (_msgSender (), owner),
             "no permission to act on behalf of this account");

    uint vaultId = vm.createVault (owner, asset, amount);
    assert (vaultId > 0);

    sellDeposits[vaultId] = true;
    emit SellDepositCreated (vaultId, owner, asset, amount);

    return vaultId;
  }

  /**
   * @dev Cancels an existing sell deposit, refunding all remaining asset
   * in the vault to the owner.
   */
  function cancelSellDeposit (uint vaultId) public
  {
    CompleteSellDeposit memory data = getSellDeposit (vaultId);
    require (data.vaultId == vaultId, "sell deposit does not exist");
    require (vm.hasAccountPermission (_msgSender (), data.owner),
             "no permission to act on behalf of the owner account");

    vm.sendFromVault (data.vaultId, data.owner, data.amount);
    delete sellDeposits[vaultId];
    emit SellDepositRemoved (vaultId);
  }

  /* ************************************************************************ */

  /**
   * @dev Complete data for a buy order, incorporating data from the
   * associated trading pool.
   */
  struct CompleteBuyOrder
  {

    /** @dev The ID of the buy order.  */
    uint orderId;

    /** @dev The trading pool to be used.  */
    uint poolId;

    /** @dev Data about the trading pool.  */
    CompletePool poolData;

    /**
     * @dev The address which owned the buyer account name when the order
     * was created.  It can only be taken if it still owns the account.
     */
    address creator;

    /** @dev The account name owning this order.  */
    string buyer;

    /** @dev The asset being bought.  */
    string asset;

    /** @dev The amount of asset that is still to be bought.  */
    uint remainingAmount;

    /** @dev The total in WCHI sats offered for the remainingAmount.  */
    uint totalSats;

  }

  /**
   * @dev Returns data about a buy order.
   */
  function getBuyOrder (uint orderId)
      public view returns (CompleteBuyOrder memory)
  {
    BuyOrder storage data = buyOrders[orderId];
    uint poolId = data.poolId;
    if (poolId == 0)
      {
        /* The buy order itself does not exist for this ID.  */
        CompleteBuyOrder memory nullOrder;
        return nullOrder;
      }

    CompletePool memory pool = getPool (poolId);
    if (pool.vaultId == 0)
      {
        /* The order ID exists, but the associated pool is removed.  */
        CompleteBuyOrder memory nullOrder;
        return nullOrder;
      }

    return CompleteBuyOrder ({
      orderId: orderId,
      poolId: poolId,
      poolData: pool,
      creator: data.creator,
      buyer: data.buyer,
      asset: pool.asset,
      remainingAmount: data.remainingAmount,
      totalSats: data.totalSats
    });
  }

  /**
   * @dev Creates a new limit buy order.
   */
  function createBuyOrder (string memory buyer, string memory asset,
                           uint amount, uint totalSats,
                           uint poolId, bytes32 checkpoint)
      public returns (uint)
  {
    require (amount > 0, "non-zero amount required");
    require (vm.hasAccountPermission (_msgSender (), buyer),
             "no permission to act on behalf of this account");
    /* There is no need to explicitly check the asset.  Since we only accept
       assets that have a valid trading pool and that pool's creation only
       allows valid assets, this is implied.  */

    CompletePool memory pool = getPool (poolId);
    /* This also implicitly checks that the pool exists, since otherwise
       the balance would be zero (and amount is larger than zero).  */
    require (pool.amount >= amount, "pool has insufficient balance");
    require (keccak256 (abi.encodePacked (pool.asset))
                == keccak256 (abi.encodePacked (asset)),
             "pool asset mismatch");
    require (vm.isCheckpoint (checkpoint), "pool checkpoint is invalid");

    /* We do not lock the WCHI, but at least sanity check that at the
       current moment, the buyer has a sufficient balance for the case
       of fully buying the order.  */
    address creator = vm.getAccountAddress (buyer);
    uint poolFee = getPoolFee (pool.relFee, totalSats);
    uint totalWchiCost = totalSats + poolFee;
    require (wchi.balanceOf (creator) >= totalWchiCost,
             "insufficient WCHI balance");
    require (wchi.allowance (creator, address (this)) >= totalWchiCost,
             "insufficient WCHI allowance");

    uint orderId = nextOrderId++;
    buyOrders[orderId] = BuyOrder ({
      poolId: poolId,
      creator: creator,
      buyer: buyer,
      remainingAmount: amount,
      totalSats: totalSats
    });
    emit BuyOrderCreated (orderId, poolId, creator, buyer, asset,
                          amount, totalSats);

    return orderId;
  }

  /**
   * @dev Cancels an existing buy order.
   */
  function cancelBuyOrder (uint orderId) public
  {
    /* We query the storage directly, instead of using getBuyOrder.  The
       latter does not return an order if the associated pool is removed,
       but we want to be able to cancel those as well (even if just
       for the sake of it, as it won't have any practical implications).  */

    BuyOrder storage data = buyOrders[orderId];
    require (data.poolId > 0, "order does not exist");
    require (vm.hasAccountPermission (_msgSender (), data.buyer),
             "no permission to act on behalf of the buyer account");

    /* Since no WCHI or anything else are locked, nothing needs to be
       done apart from updating the order book.  */
    delete buyOrders[orderId];
    emit BuyOrderRemoved (orderId);
  }

  /* ************************************************************************ */

}
