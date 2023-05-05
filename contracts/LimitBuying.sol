// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./IDemocritConfig.sol";
import "./LimitSelling.sol";
import "./VaultManager.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @dev This contract adds support for limit buy orders, together with the
 * trading pools needed for it, to Democrit.
 */
contract LimitBuying is LimitSelling, EIP712
{

  string public constant EIP712_NAME = "Democrit";
  string public constant EIP712_VERSION = "1";

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

  /**
   * @dev We use "nonce" values for the EIP712 pool signatures.  They are not
   * single use, but a signature is only valid when it commits to the current
   * nonce explicitly, and the nonce can be bumped on-demand to invalidate
   * all made signatures in case that is necessary for some reason.
   *
   * The nonces are tied to the operator account name.
   */
  mapping (string => uint256) public signatureNonce;

  /* ************************************************************************ */

  constructor (VaultManager v)
    LimitSelling(v)
    EIP712(EIP712_NAME, EIP712_VERSION)
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

  /**
   * @dev Returns the EIP712 domain separator used for signatures
   * verified by this contract.
   */
  function domainSeparator () public view returns (bytes32)
  {
    return _domainSeparatorV4 ();
  }

  /**
   * @dev The data signed by a trading pool with EIP712 when they have
   * verified a given vault.
   */
  struct VaultCheck
  {

    /** @dev The vault ID they have verified.  */
    uint256 vaultId;

    /** @dev The checkpoint at which they have verified the vault exists.  */
    bytes32 checkpoint;

    /* The EIP712 signed struct also includes a nonce here, which is implied
       by the contract state and thus not passed explicitly.  */

  }

  /**
   * @dev Verifies if a given vault check has been signed correctly by
   * the owner of the given account or an address authorised for it.
   *
   * Note that this only verifies if the signature is valid.  It does not check
   * if the vault exists, the checkpoint is valid, or anything else like that.
   */
  function isPoolSignatureValid (string memory operator,
                                 VaultCheck calldata vault,
                                 bytes calldata signature)
      public view returns (bool)
  {
    bytes memory body = abi.encode (
      keccak256 ("VaultCheck(uint256 vaultId,bytes32 checkpoint,uint256 nonce)"),
      vault.vaultId,
      vault.checkpoint,
      signatureNonce[operator]
    );
    bytes32 digest = _hashTypedDataV4 (keccak256 (body));

    address signer = ECDSA.recover (digest, signature);
    return vm.hasAccountPermission (signer, operator);
  }

  /**
   * @dev Bumps the signature nonce for the given pool.  Returns the new
   * nonce for the pool.
   */
  function bumpSignatureNonce (string memory operator) public returns (uint256)
  {
    require (vm.hasAccountPermission (_msgSender (), operator),
             "no permission to act on behalf of the pool operator");
    return ++signatureNonce[operator];
  }

  /* ************************************************************************ */

  /**
   * @dev Arguments required for accepting a buy order ("market sell").
   * They are collected into a struct so that we can provide also a method
   * for batch-accepting multiple orders easily.
   */
  struct AcceptedBuyOrder
  {

    /** The order ID being accepted.  */
    uint orderId;

    /** The amount of asset being sold.  */
    uint amountSold;

    /** Sell deposit and checkpoint at which the pool has verified it.  */
    VaultCheck deposit;

    /** The pool's signature on the vault check.  */
    bytes signature;

    /* The limit price of orders is fixed once the order is created, so that
       we do not need to explicitly specify the expected price in sats in the
       order.

       The trading pool's ID is implicit from the order accepted,
       and the seller account is fixed by the used sell deposit.  */

  }

  /**
   * @dev Accepts a limit buy order, selling all or part of the desired asset
   * utilising a sell deposit and trading pool.
   */
  function acceptBuyOrder (AcceptedBuyOrder calldata args) public virtual
  {
    CompleteBuyOrder memory order = getBuyOrder (args.orderId);
    require (order.orderId > 0, "order does not exist");
    assert (order.poolData.vaultId > 0);
    /* Calculating the purchase amount of sats already checks the
       amount bought is non-zero and within the available limits for
       the order.  The limits for the sell deposit and trading pool balances
       are checked when we attempt to transfer from the respective vaults.  */
    uint sats = getSatsForPurchase (order.remainingAmount, order.totalSats,
                                    args.amountSold);
    uint fee = getPoolFee (order.poolData.relFee, sats);

    require (vm.isCheckpoint (args.deposit.checkpoint),
             "vault checkpoint is invalid");
    require (isPoolSignatureValid (order.poolData.operator, args.deposit,
                                   args.signature),
             "pool signature of the vault check is invalid");
    /* The order creation already verifies that the pool asset matches
       the order's asset.  */

    CompleteSellDeposit memory deposit = getSellDeposit (args.deposit.vaultId);
    require (deposit.vaultId > 0, "sell deposit does not exist");
    require (keccak256 (abi.encodePacked (deposit.asset))
                == keccak256 (abi.encodePacked (order.asset)),
             "deposit asset mismatch");
    require (vm.hasAccountPermission (_msgSender (), deposit.owner),
             "no permission to act on behalf of the deposit owner");

    address buyerAddress = vm.getAccountAddress (order.buyer);
    require (buyerAddress == order.creator, "buyer name has been transferred");
    address poolAddress = vm.getAccountAddress (order.poolData.operator);

    require (wchi.transferFrom (buyerAddress, _msgSender (), sats),
             "WCHI transfer failed");
    require (wchi.transferFrom (buyerAddress, poolAddress, fee),
             "WCHI transfer failed");
    vm.sendFromVault (deposit.vaultId, order.poolData.operator,
                      args.amountSold);
    vm.sendFromVault (order.poolData.vaultId, order.buyer, args.amountSold);

    emit Trade (order.asset, args.amountSold, sats, deposit.owner, order.buyer);

    bool poolEmptied = (order.poolData.amount == args.amountSold);
    if (poolEmptied)
      {
        delete pools[order.poolData.vaultId];
        emit PoolRemoved (order.poolData.vaultId);
      }
    else
      {
        uint newRemaining = order.poolData.amount - args.amountSold;
        assert (newRemaining > 0);
        emit PoolUpdated (order.poolData.vaultId, newRemaining);
      }

    if (args.amountSold == order.remainingAmount || poolEmptied)
      {
        /* Note that if the pool was emptied (instead of the order fulfilled
           completely), we can still delete the order since there are no
           tokens or assets locked/reserved for buy orders.  */
        delete buyOrders[order.orderId];
        emit BuyOrderRemoved (order.orderId);
      }
    else
      {
        uint newRemaining = order.remainingAmount - args.amountSold;
        assert (newRemaining > 0);
        uint newSats = order.totalSats - sats;

        BuyOrder storage ptr = buyOrders[order.orderId];
        assert (ptr.poolId > 0);
        ptr.remainingAmount = newRemaining;
        ptr.totalSats = newSats;
        emit BuyOrderUpdated (order.orderId, newRemaining, newSats);
      }

    if (args.amountSold == deposit.amount)
      {
        delete sellDeposits[deposit.vaultId];
        emit SellDepositRemoved (deposit.vaultId);
      }
    else
      {
        uint newRemaining = deposit.amount - args.amountSold;
        assert (newRemaining > 0);
        emit SellDepositUpdated (deposit.vaultId, newRemaining);
      }
  }

  /**
   * @dev Accepts a batch of limit buy orders as per acceptBuyOrder.
   */
  function acceptBuyOrders (AcceptedBuyOrder[] calldata orders) public
  {
    for (uint i = 0; i < orders.length; ++i)
      acceptBuyOrder (orders[i]);
  }

  /* ************************************************************************ */

}
