// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./TradingTest.sol";
import "../src/LimitBuying.sol";

contract LimitBuyingTest is TradingTest
{

  address public immutable pool;
  address public immutable poolSigner;

  constructor ()
  {
    pool = vm.addr (4);
    poolSigner = vm.addr (5);

    vm.label (pool, "pool");
    vm.label (poolSigner, "pool signer");
  }

  function setUp () public override
  {
    TradingTest.setUp ();
    setupPoolOperator (pool, "pool", poolSigner);
  }

  /* ************************************************************************ */

  /**
   * @dev Asserts that no pool with the given ID exists.
   */
  function assertNoPool (uint256 vaultId) internal view
  {
    assertPoolNull (dem.getPool (vaultId));
  }

  /**
   * @dev Assets that the pool with the given ID matches the expected values.
   */
  function assertPool (uint256 vaultId, string memory operator,
                       string memory asset, uint256 amount, uint64 fee)
      internal view
  {
    assertPoolData (dem.getPool (vaultId),
                    vaultId, operator, asset, amount, fee);
  }

  function test_getPoolFee () public
  {
    vm.expectRevert ();
    dem.getPoolFee (100, type (uint256).max);

    assertEq (dem.getPoolFee (0, 100), 0);
    assertEq (dem.getPoolFee (100, 0), 0);
    assertEq (dem.getPoolFee (10, 256), 26);
    assertEq (dem.getPoolFee (1, 1), 1);
    assertEq (dem.getPoolFee (1, 100), 1);

    uint256 large = 2 ** 128;
    assertEq (dem.getPoolFee (100, large), large);
  }

  function test_nonExistingPool () public view
  {
    assertNoPool (123);
  }

  function test_createVerifiesAssetAmountAndFee () public
  {
    vm.startPrank (pool);

    vm.expectRevert ("non-zero amount required");
    dem.createPool ("pool", "", "gold", 0, 0);

    vm.expectRevert ("invalid asset for vault");
    dem.createPool ("pool", "", "invalid", 1, 1);

    vm.expectRevert ("fee too high");
    dem.createPool ("pool", "", "gold", 1, 11);

    vm.stopPrank ();
  }

  function test_createVerifiesSenderPermission () public
  {
    vm.prank (seller);
    vm.expectRevert ("no permission to act on behalf of this account");
    dem.createPool ("pool", "", "gold", 1, 1);
  }

  function test_createPool () public
  {
    vm.startPrank (pool);
    dem.createPool ("pool", "", "gold", 5, 0);
    dem.createPool ("pool", "", "silver", 100, 10);
    vm.stopPrank ();

    assertVault (vman, 1, "pool", "gold", 5);
    assertVault (vman, 2, "pool", "silver", 100);

    assertPool (1, "pool", "gold", 5, 0);
    assertPool (2, "pool", "silver", 100, 10);
  }

  function test_cancelNonExistingPool () public
  {
    vm.prank (pool);
    vm.expectRevert ("trading pool does not exist");
    dem.cancelPool (1);
  }

  function test_cancelVerifiesPermission () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 5, 0);

    vm.prank (buyer);
    vm.expectRevert ("no permission to act on behalf of the operator account");
    dem.cancelPool (1);
  }

  function test_cancelPool () public
  {
    vm.startPrank (pool);
    dem.createPool ("pool", "", "gold", 5, 10);
    dem.createPool ("pool", "", "silver", 100, 1);
    vm.stopPrank ();

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to pool\"}}}",
        address (vman));
    vm.prank (pool);
    dem.cancelPool (1);

    assertNoPool (1);
    assertNoVault (vman, 1);

    assertPool (2, "pool", "silver", 100, 1);
    assertVault (vman, 2, "pool", "silver", 100);
  }

  /* ************************************************************************ */

  /**
   * @dev Asserts that no deposit with the given ID exists.
   */
  function assertNoDeposit (uint256 vaultId) internal view
  {
    LimitBuying.CompleteSellDeposit memory data = dem.getSellDeposit (vaultId);
    assertEq (data.vaultId, 0);
    assertEq (data.owner, "");
    assertEq (data.asset, "");
    assertEq (data.amount, 0);
  }

  /**
   * @dev Asserts that the sell deposit with the given ID matches
   * the expected values.
   */
  function assertDeposit (uint256 vaultId, string memory owner,
                          string memory asset, uint256 amount)
      internal view
  {
    LimitBuying.CompleteSellDeposit memory data = dem.getSellDeposit (vaultId);
    assertEq (data.vaultId, vaultId);
    assertEq (data.owner, owner);
    assertEq (data.asset, asset);
    assertEq (data.amount, amount);
  }

  function test_nonExistingSellDeposit () public view
  {
    assertNoDeposit (123);
  }

  function test_createDepositVerifiesAssetAndAmount () public
  {
    vm.startPrank (seller);

    vm.expectRevert ("non-zero amount required");
    dem.createSellDeposit ("seller", "gold", 0);

    vm.expectRevert ("invalid asset for vault");
    dem.createSellDeposit ("seller", "invalid", 1);

    vm.stopPrank ();
  }

  function test_createDepositVerifiesSenderPermission () public
  {
    vm.prank (buyer);
    vm.expectRevert ("no permission to act on behalf of this account");
    dem.createSellDeposit ("seller", "gold", 1);
  }

  function test_createSellDeposit () public
  {
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 5);

    assertVault (vman, 1, "seller", "gold", 5);
    assertDeposit (1, "seller", "gold", 5);
  }

  function test_cancelNonExistingDeposit () public
  {
    vm.prank (seller);
    vm.expectRevert ("sell deposit does not exist");
    dem.cancelSellDeposit (1);
  }

  function test_cancelDepositVerifiesPermission () public
  {
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 5);

    vm.prank (buyer);
    vm.expectRevert ("no permission to act on behalf of the owner account");
    dem.cancelSellDeposit (1);
  }

  function test_cancelSellDeposit () public
  {
    vm.startPrank (seller);
    dem.createSellDeposit ("seller", "gold", 5);
    dem.createSellDeposit ("seller", "silver", 100);
    vm.stopPrank ();

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to seller\"}}}",
        address (vman));
    vm.prank (seller);
    dem.cancelSellDeposit (1);

    assertNoDeposit (1);
    assertNoVault (vman, 1);

    assertDeposit (2, "seller", "silver", 100);
    assertVault (vman, 2, "seller", "silver", 100);
  }

  /* ************************************************************************ */

  /**
   * @dev Asserts that no buy order with the given ID exists.
   */
  function assertNoBuyOrder (uint256 orderId) internal view
  {
    assertBuyOrderNull (dem.getBuyOrder (orderId));
  }

  /**
   * @dev Asserts that the buy order with the given ID matches
   * the expected values.
   */
  function assertBuyOrder (uint256 orderId, uint256 poolId,
                           string memory poolOperator,
                           uint256 poolAmount, uint64 poolFee,
                           address creator, string memory buy,
                           string memory asset,
                           uint256 remainingAmount, uint256 totalSats)
      internal view
  {
    assertBuyOrderData (dem.getBuyOrder (orderId),
                        orderId, poolId, poolOperator,
                        poolAmount, poolFee,
                        creator, buy, asset,
                        remainingAmount, totalSats);
  }

  /**
   * @dev Creates a new trading pool and checkpoints it.
   */
  function createCheckpointedPool (string memory asset, uint256 amount,
                                   uint64 fee)
      internal returns (uint256 poolId, bytes32 cpHash)
  {
    poolId = vman.getNextVaultId ();
    vm.prank (pool);
    dem.createPool ("pool", "", asset, amount, fee);
    cpHash = createCheckpoint ();
  }

  function test_nonExistingBuyOrder () public view
  {
    assertNoBuyOrder (123);
  }

  function test_createBuyOrderVerifiesAmountAndPermission () public
  {
    (uint256 poolId, bytes32 cpHash) = createCheckpointedPool ("gold", 10, 1);

    vm.prank (buyer);
    vm.expectRevert ("non-zero amount required");
    dem.createBuyOrder ("buyer", "gold", 0, 10, poolId, cpHash);

    vm.prank (seller);
    vm.expectRevert ("no permission to act on behalf of this account");
    dem.createBuyOrder ("buyer", "gold", 1, 10, poolId, cpHash);
  }

  function test_createBuyOrderVerifiesPool () public
  {
    bytes32 noCheckpoint = blockhash (block.number - 1);
    (uint256 poolId, bytes32 cpHash) = createCheckpointedPool ("gold", 10, 1);

    vm.prank (buyer);
    vm.expectRevert ("pool has insufficient balance");
    dem.createBuyOrder ("buyer", "gold", 11, 10, 123, cpHash);

    vm.prank (buyer);
    vm.expectRevert ("pool has insufficient balance");
    dem.createBuyOrder ("buyer", "gold", 11, 10, poolId, cpHash);

    vm.prank (buyer);
    vm.expectRevert ("pool asset mismatch");
    dem.createBuyOrder ("buyer", "silver", 3, 10, poolId, cpHash);

    vm.prank (buyer);
    vm.expectRevert ("pool checkpoint is invalid");
    dem.createBuyOrder ("buyer", "gold", 3, 10, poolId, noCheckpoint);
  }

  function test_createBuyOrderVerifiesWchi () public
  {
    vm.startPrank (pool);
    dem.createPool ("pool", "", "gold", 100, 10);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.stopPrank ();
    bytes32 cpHash = createCheckpoint ();

    vm.startPrank (buyer);
    vm.expectRevert ("insufficient WCHI balance");
    dem.createBuyOrder ("buyer", "gold", 1, BALANCE - 1, 1, cpHash);

    vm.expectRevert ("insufficient WCHI balance");
    dem.createBuyOrder ("buyer", "gold", 1, BALANCE + 1, 2, cpHash);

    wchi.approve (address (dem), BALANCE - 1);

    vm.expectRevert ("insufficient WCHI allowance");
    dem.createBuyOrder ("buyer", "gold", 1, BALANCE, 2, cpHash);
  }

  function test_createBuyOrder () public
  {
    (uint256 poolId, bytes32 cpHash) = createCheckpointedPool ("gold", 100, 0);

    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, BALANCE, poolId, cpHash);

    assertBuyOrder (101, poolId, "pool", 100, 0,
                    buyer, "buyer", "gold", 100, BALANCE);
    /* No WCHI is actually moved by creating the buy order.  */
    assertEq (wchi.balanceOf (buyer), BALANCE);
  }

  function test_buyOrderWithCancelledPool () public
  {
    (uint256 poolId, bytes32 cpHash) = createCheckpointedPool ("gold", 100, 0);

    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash);

    vm.prank (pool);
    dem.cancelPool (poolId);

    assertNoBuyOrder (101);
  }

  function test_cancelNonExistingBuyOrder () public
  {
    vm.prank (buyer);
    vm.expectRevert ("order does not exist");
    dem.cancelBuyOrder (123);
  }

  function test_cancelBuyOrderVerifiesPermission () public
  {
    (uint256 poolId, bytes32 cpHash) = createCheckpointedPool ("gold", 100, 0);

    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash);

    vm.prank (pool);
    vm.expectRevert ("no permission to act on behalf of the buyer account");
    dem.cancelBuyOrder (101);
  }

  function test_cancelBuyOrder () public
  {
    (uint256 poolId, bytes32 cpHash) = createCheckpointedPool ("gold", 100, 0);

    vm.startPrank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash);
    dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash);

    dem.cancelBuyOrder (101);
    assertNoBuyOrder (101);
    assertBuyOrder (102, poolId, "pool", 100, 0,
                    buyer, "buyer", "gold", 100, 10);

    vm.expectRevert ("order does not exist");
    dem.cancelBuyOrder (101);
    vm.stopPrank ();

    /* Even if the pool is cancelled and the buy order "hidden", it can be
       cancelled.  But cancelling again will fail, as this is a "real" check
       whether or not the data exists in storage.  */
    vm.prank (pool);
    dem.cancelPool (poolId);
    assertNoBuyOrder (102);

    vm.prank (buyer);
    dem.cancelBuyOrder (102);

    vm.prank (buyer);
    vm.expectRevert ("order does not exist");
    dem.cancelBuyOrder (102);
  }

  /* ************************************************************************ */

  function test_eip712DomainSeparator () public view
  {
    bytes32 typeHash = keccak256 (
      "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 domainHash = keccak256 (abi.encode (
      typeHash,
      keccak256 (bytes (dem.EIP712_NAME ())),
      keccak256 (bytes (dem.EIP712_VERSION ())),
      block.chainid,
      address (dem)
    ));
    assertEq (dem.domainSeparator (), domainHash);
  }

  function test_poolSignatureVerification () public
  {
    bytes32 fakeCp = blockhash (block.number - 1);
    (LimitBuying.VaultCheck memory vault, bytes memory signature)
        = signVaultCheck ("pool", 5, 42, fakeCp);

    assertTrue (dem.isPoolSignatureValid ("pool", vault, signature));

    assertFalse (dem.isPoolSignatureValid ("buyer", vault, signature));

    LimitBuying.VaultCheck memory vault2 = LimitBuying.VaultCheck ({
      vaultId: vault.vaultId + 1,
      checkpoint: vault.checkpoint
    });
    assertFalse (dem.isPoolSignatureValid ("pool", vault2, signature));

    vm.prank (pool);
    dem.bumpSignatureNonce ("pool");
    (LimitBuying.VaultCheck memory vault3, bytes memory signature3)
        = signVaultCheck ("pool", 5, 42, fakeCp);
    assertFalse (dem.isPoolSignatureValid ("pool", vault, signature));
    assertTrue (dem.isPoolSignatureValid ("pool", vault3, signature3));
  }

  /* ************************************************************************ */

  function test_acceptFailsForNonExisting () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 100);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    /* The order itself does not exist.  */
    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 123,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("order does not exist");
    dem.acceptBuyOrder (args);

    /* The sell deposit does not exist.  */
    (LimitBuying.VaultCheck memory deposit2, bytes memory signature2)
        = signVaultCheck ("pool", 5, 987, cpHash);
    args.orderId = 101;
    args.deposit = deposit2;
    args.signature = signature2;
    vm.prank (seller);
    vm.expectRevert ("sell deposit does not exist");
    dem.acceptBuyOrder (args);

    /* The order "exists", but the associated pool has been removed.  */
    vm.prank (pool);
    dem.cancelPool (1);
    args.deposit = deposit;
    args.signature = signature;
    vm.prank (seller);
    vm.expectRevert ("order does not exist");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsForInvalidAmount () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 100);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 0,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("amount bought must be non-zero");
    dem.acceptBuyOrder (args);

    args.amountSold = 11;
    vm.prank (seller);
    vm.expectRevert ("amount exceeds remaining");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsIfAmountExceedsPool () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 10, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 100);
    bytes32 cpHash = createCheckpoint ();
    /* We cannot create a buy order that is larger as the pool already,
       so we create two "competing" orders that fit, and then partially
       accept both which goes over the pool capacity.  */
    vm.startPrank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    vm.stopPrank ();
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 6,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    dem.acceptBuyOrder (args);

    args.orderId = 102;
    vm.prank (seller);
    vm.expectRevert ("not enough funds in vault");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsIfAmountExceedsDeposit () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 11,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("not enough funds in vault");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsForInvalidVaultCheck () public
  {
    bytes32 noCheckpoint = blockhash (block.number - 1);
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 50, 1, cpHash);

    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, noCheckpoint);
    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("vault checkpoint is invalid");
    dem.acceptBuyOrder (args);

    (LimitBuying.VaultCheck memory deposit2, bytes memory signature2)
        = signVaultCheck ("pool", 5, 2, cpHash);
    vm.prank (pool);
    acc.setApprovalForAll (poolSigner, false);
    args.deposit = deposit2;
    args.signature = signature2;
    vm.prank (seller);
    vm.expectRevert ("pool signature of the vault check is invalid");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsForWrongDepositAsset () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "silver", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("deposit asset mismatch");
    dem.acceptBuyOrder (args);
  }

  function test_acceptVerifiesAccountPermission () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    vm.prank (buyer);
    vm.expectRevert ("no permission to act on behalf of the deposit owner");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsIfBuyerNameTransferred () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    uint256 tokenId = acc.tokenIdForName ("p", "buyer");
    vm.prank (buyer);
    acc.safeTransferFrom (buyer, seller, tokenId);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("buyer name has been transferred");
    dem.acceptBuyOrder (args);
  }

  function test_acceptFailsForInsufficientWchiBalance () public
  {
    /* When creating a buy order, the balance is checked.  So we need to
       create the orders with a higher balance, and then decrease it afterwards
       to a lower one that is insufficient to accept the orders in full.  */
    uint256 lowBalance = BALANCE / 100;

    vm.startPrank (pool);
    dem.createPool ("pool", "", "gold", 100, 1);
    dem.createPool ("pool", "", "gold", 100, 0);
    vm.stopPrank ();
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 100);
    bytes32 cpHash = createCheckpoint ();
    vm.startPrank (buyer);
    dem.createBuyOrder ("buyer", "gold", 20, 2 * lowBalance, 1, cpHash);
    dem.createBuyOrder ("buyer", "gold", 20, 2 * lowBalance, 2, cpHash);
    vm.stopPrank ();
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 3, cpHash);

    setWchiBalance (buyer, lowBalance);

    /* While the buyer could in theory afford all of the asset bought, it will
       not be able to affort the fee charged on top.  */
    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 10,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    dem.acceptBuyOrder (args);

    /* Here there is no fee, but the buyer cannot afford the amount bought.  */
    args.orderId = 102;
    args.amountSold = 11;
    vm.prank (seller);
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    dem.acceptBuyOrder (args);
  }

  /* ************************************************************************ */

  function test_acceptBuyOrderCompletely () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 10, 10);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    XayaEnvTest.ExpectedMove[] memory expectedMoves
        = new XayaEnvTest.ExpectedMove[] (2);
    expectedMoves[0] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"10 gold from ctrl:2 to pool\"}}}",
      mover: address (vman)
    });
    expectedMoves[1] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"10 gold from ctrl:1 to buyer\"}}}",
      mover: address (vman)
    });
    expectMoves (expectedMoves);
    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 10,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    dem.acceptBuyOrder (args);

    assertNoBuyOrder (101);
    assertNoPool (1);
    assertNoVault (vman, 1);
    assertNoDeposit (2);
    assertNoVault (vman, 2);

    assertEq (wchi.balanceOf (seller), 50);
    assertEq (wchi.balanceOf (pool), 5);
    assertEq (wchi.balanceOf (buyer), BALANCE - 55);
  }

  function test_acceptBuyOrderPartially () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 10, 10);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    XayaEnvTest.ExpectedMove[] memory expectedMoves
        = new XayaEnvTest.ExpectedMove[] (2);
    expectedMoves[0] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:2 to pool\"}}}",
      mover: address (vman)
    });
    expectedMoves[1] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to buyer\"}}}",
      mover: address (vman)
    });
    expectMoves (expectedMoves);
    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    dem.acceptBuyOrder (args);

    assertBuyOrder (101, 1, "pool", 5, 10,
                    buyer, "buyer", "gold", 5, 25);
    assertPool (1, "pool", "gold", 5, 10);
    assertVault (vman, 1, "pool", "gold", 5);
    assertDeposit (2, "seller", "gold", 5);
    assertVault (vman, 2, "seller", "gold", 5);

    assertEq (wchi.balanceOf (seller), 25);
    assertEq (wchi.balanceOf (pool), 3);
    assertEq (wchi.balanceOf (buyer), BALANCE - 28);
  }

  function test_removeBuyOrderIfPoolEmptied () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 20, 10);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 20);
    bytes32 cpHash = createCheckpoint ();
    vm.startPrank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    dem.createBuyOrder ("buyer", "gold", 20, 50, 1, cpHash);
    vm.stopPrank ();
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    LimitBuying.AcceptedBuyOrder memory args = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 10,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    dem.acceptBuyOrder (args);

    args.orderId = 102;
    vm.prank (seller);
    dem.acceptBuyOrder (args);

    assertNoBuyOrder (101);
    assertNoBuyOrder (102);
    assertNoPool (1);
    assertNoVault (vman, 1);

    /* Verify the buy order is really removed and not just hidden after
       the pool got removed.  */
    vm.prank (buyer);
    vm.expectRevert ("order does not exist");
    dem.cancelBuyOrder (102);
  }

  function test_acceptBuyOrdersBatch () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 10, 10);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 50, 1, cpHash);
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);

    XayaEnvTest.ExpectedMove[] memory expectedMoves
        = new XayaEnvTest.ExpectedMove[] (4);
    expectedMoves[0] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:2 to pool\"}}}",
      mover: address (vman)
    });
    expectedMoves[1] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to buyer\"}}}",
      mover: address (vman)
    });
    expectedMoves[2] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"3 gold from ctrl:2 to pool\"}}}",
      mover: address (vman)
    });
    expectedMoves[3] = XayaEnvTest.ExpectedMove ({
      name: "ctrl",
      mv: "{\"g\":{\"gid\":{\"send\": \"3 gold from ctrl:1 to buyer\"}}}",
      mover: address (vman)
    });
    expectMoves (expectedMoves);
    LimitBuying.AcceptedBuyOrder[] memory orders
        = new LimitBuying.AcceptedBuyOrder[] (2);
    orders[0] = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 5,
      deposit: deposit,
      signature: signature
    });
    orders[1] = LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 3,
      deposit: deposit,
      signature: signature
    });
    vm.prank (seller);
    dem.acceptBuyOrders (orders);

    assertEq (wchi.balanceOf (seller), 40);
    assertEq (wchi.balanceOf (pool), 5);
    assertEq (wchi.balanceOf (buyer), BALANCE - 45);
  }

  /* ************************************************************************ */

  function test_distinguishOrdersPoolsAndDeposits () public
  {
    dem.setNextOrderId (1);

    vm.prank (seller);
    dem.createSellOrder ("seller", "gold", 1, 10);
    vm.prank (pool);
    dem.createPool ("pool", "", "silver", 2, 10);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "copper", 3);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "silver", 1, 1, 2, cpHash);

    assertVault (vman, 1, "seller", "gold", 1);
    assertVault (vman, 2, "pool", "silver", 2);
    assertVault (vman, 3, "seller", "copper", 3);

    assertSellOrderData (dem.getSellOrder (1), 1, 1, seller,
                         "seller", "gold", 1, 10);
    assertNoPool (1);
    assertNoDeposit (1);
    assertNoBuyOrder (1);

    assertSellOrderNull (dem.getSellOrder (2));
    assertPool (2, "pool", "silver", 2, 10);
    assertNoDeposit (2);
    /* The buy order also has ID 2, since orders have their own ID series
       and it also does not imply a vault.  */
    assertBuyOrder (2, 2, "pool", 2, 10,
                    buyer, "buyer", "silver", 1, 1);

    assertSellOrderNull (dem.getSellOrder (3));
    assertNoPool (3);
    assertDeposit (3, "seller", "copper", 3);
    assertNoBuyOrder (3);

    vm.startPrank (seller);
    vm.expectRevert ("order does not exist");
    dem.cancelSellOrder (2);
    vm.expectRevert ("order does not exist");
    dem.cancelSellOrder (3);

    vm.startPrank (pool);
    vm.expectRevert ("trading pool does not exist");
    dem.cancelPool (1);
    vm.expectRevert ("trading pool does not exist");
    dem.cancelPool (3);

    vm.startPrank (seller);
    vm.expectRevert ("sell deposit does not exist");
    dem.cancelSellDeposit (1);
    vm.expectRevert ("sell deposit does not exist");
    dem.cancelSellDeposit (2);

    vm.startPrank (buyer);
    vm.expectRevert ("order does not exist");
    dem.cancelBuyOrder (1);
    vm.expectRevert ("order does not exist");
    dem.cancelBuyOrder (3);
    vm.stopPrank ();

    vm.prank (seller);
    dem.cancelSellOrder (1);
    vm.prank (pool);
    dem.cancelPool (2);
    vm.prank (seller);
    dem.cancelSellDeposit (3);
    vm.prank (buyer);
    dem.cancelBuyOrder (2);

    assertNoVault (vman, 1);
    assertNoVault (vman, 2);
    assertNoVault (vman, 3);
    assertNoBuyOrder (2);
  }

}
