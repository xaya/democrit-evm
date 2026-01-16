// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./TradingTest.sol";
import "../src/LimitSelling.sol";

contract LimitSellingTest is TradingTest
{

  /**
   * @dev Asserts that no sell order with the given ID exists.
   */
  function assertNoSellOrder (uint256 orderId) internal view
  {
    assertSellOrderNull (dem.getSellOrder (orderId));
  }

  /**
   * @dev Assets that the sell order with the given ID matches
   * the expected values.
   */
  function assertSellOrder (uint256 orderId, uint256 vaultId, address creator,
                            string memory sel, string memory asset,
                            uint256 amount, uint256 sats)
      internal view
  {
    assertSellOrderData (dem.getSellOrder (orderId), orderId, vaultId,
                         creator, sel, asset, amount, sats);
  }

  /**
   * @dev Creates a new sell order and checkpoints the associated vault
   * afterwards.
   */
  function createCheckpointedOrder (string memory seller, string memory asset,
                                    uint256 amount, uint256 sats, address from)
      internal returns (uint256 orderId, bytes32 cpHash)
  {
    orderId = dem.nextOrderId ();
    vm.prank (from);
    dem.createSellOrder (seller, asset, amount, sats);
    cpHash = createCheckpoint ();
  }

  /* ************************************************************************ */

  function test_getSatsForPurchase () public
  {
    vm.expectRevert ("expected non-zero remaining amount");
    dem.getSatsForPurchase (0, 10, 1);

    vm.expectRevert ("amount bought must be non-zero");
    dem.getSatsForPurchase (10, 10, 0);

    vm.expectRevert ("amount exceeds remaining");
    dem.getSatsForPurchase (10, 10, 11);

    vm.expectRevert ();
    dem.getSatsForPurchase (2, type (uint256).max, 1);

    /* Some examples with full purchases.  */
    assertEq (dem.getSatsForPurchase (100, 42, 100), 42);
    assertEq (dem.getSatsForPurchase (100, 0, 100), 0);
    assertEq (dem.getSatsForPurchase (1, 1, 1), 1);

    /* These two would overflow, but work due to the full purchase
       short-circuit condition.  */
    assertEq (dem.getSatsForPurchase (2, type (uint256).max, 2),
              type (uint256).max);
    assertEq (dem.getSatsForPurchase (type (uint256).max, 2,
                                      type (uint256).max), 2);

    /* Zero purchase price is ok.  */
    assertEq (dem.getSatsForPurchase (100, 0, 20), 0);
    assertEq (dem.getSatsForPurchase (type (uint256).max, 0, 100), 0);

    /* Rounding up to the next sat.  */
    assertEq (dem.getSatsForPurchase (100, 1, 1), 1);
    assertEq (dem.getSatsForPurchase (100, 1, 99), 1);

    /* Proportional amount.  */
    assertEq (dem.getSatsForPurchase (100, 1000, 42), 420);
    assertEq (dem.getSatsForPurchase (100, 5, 33), 2);
  }

  /* ************************************************************************ */

  function test_nonExistingOrder () public view
  {
    assertNoSellOrder (123);
  }

  function test_createVerifiesAssetAndAmount () public
  {
    vm.startPrank (seller);

    vm.expectRevert ("non-zero amount required");
    dem.createSellOrder ("seller", "gold", 0, 0);

    vm.expectRevert ("invalid asset for vault");
    dem.createSellOrder ("seller", "invalid", 1, 1);

    vm.stopPrank ();
  }

  function test_createVerifiesSenderPermission () public
  {
    vm.prank (buyer);
    vm.expectRevert ("no permission to act on behalf of this account");
    dem.createSellOrder ("seller", "gold", 1, 1);
  }

  function test_createSellOrder () public
  {
    vm.startPrank (seller);
    dem.createSellOrder ("seller", "gold", 5, 10);
    dem.createSellOrder ("seller", "silver", 100, 1);
    vm.stopPrank ();

    assertVault (vman, 1, "seller", "gold", 5);
    assertVault (vman, 2, "seller", "silver", 100);

    assertSellOrder (101, 1, seller, "seller", "gold", 5, 10);
    assertSellOrder (102, 2, seller, "seller", "silver", 100, 1);
  }

  /* ************************************************************************ */

  function test_cancelNonExistingOrder () public
  {
    vm.prank (seller);
    dem.createSellOrder ("seller", "gold", 5, 10);

    vm.prank (seller);
    vm.expectRevert ("order does not exist");
    dem.cancelSellOrder (102);
  }

  function test_cancelVerifiesPermission () public
  {
    vm.prank (seller);
    dem.createSellOrder ("seller", "gold", 5, 10);

    vm.prank (buyer);
    vm.expectRevert ("no permission to act on behalf of the seller account");
    dem.cancelSellOrder (101);
  }

  function test_cancelSellOrder () public
  {
    vm.startPrank (seller);
    dem.createSellOrder ("seller", "gold", 5, 10);
    dem.createSellOrder ("seller", "silver", 100, 1);
    vm.stopPrank ();

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to seller\"}}}",
        address (vman));
    vm.prank (seller);
    dem.cancelSellOrder (101);

    assertNoSellOrder (101);
    assertNoVault (vman, 1);

    assertSellOrder (102, 2, seller, "seller", "silver", 100, 1);
    assertVault (vman, 2, "seller", "silver", 100);
  }

  /* ************************************************************************ */

  function test_acceptNonExistingOrder () public
  {
    bytes32 notCheckpointed = blockhash (block.number - 1);
    vm.prank (buyer);
    vm.expectRevert ("order does not exist");
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        123, 1, "buyer", notCheckpointed));
  }

  function test_acceptVerifiesCheckpoint () public
  {
    vm.prank (seller);
    dem.createSellOrder ("seller", "gold", 5, 10);
    uint256 height = block.number;
    vm.roll (height + 1);
    bytes32 notCheckpointed = blockhash (height);

    vm.prank (buyer);
    vm.expectRevert ("vault checkpoint is invalid");
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        101, 1, "buyer", notCheckpointed));
  }

  function test_acceptFailsForInvalidAmountBought () public
  {
    (uint256 orderId, bytes32 cpHash)
        = createCheckpointedOrder ("seller", "gold", 5, 10, seller);

    vm.prank (buyer);
    vm.expectRevert ("amount bought must be non-zero");
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        orderId, 0, "buyer", cpHash));

    vm.prank (buyer);
    vm.expectRevert ("amount exceeds remaining");
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        orderId, 6, "buyer", cpHash));
  }

  function test_acceptFailsIfWchiBalanceInsufficient () public
  {
    (uint256 orderId, bytes32 cpHash)
        = createCheckpointedOrder ("seller", "gold", 5, BALANCE + 1, seller);

    vm.prank (buyer);
    vm.expectRevert ("ERC20: transfer amount exceeds balance");
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        orderId, 5, "buyer", cpHash));
  }

  function test_acceptFailsIfSellerNameTransferred () public
  {
    (uint256 orderId, bytes32 cpHash)
        = createCheckpointedOrder ("seller", "gold", 5, 10, seller);

    uint256 tokenId = acc.tokenIdForName ("p", "seller");
    vm.prank (seller);
    acc.safeTransferFrom (seller, buyer, tokenId);

    vm.prank (buyer);
    vm.expectRevert ("seller name has been transferred");
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        orderId, 5, "buyer", cpHash));

    /* Cancelling the order is still possible, so the new owner can get
       back the locked funds.  */
    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to seller\"}}}",
        address (vman));
    vm.prank (buyer);
    dem.cancelSellOrder (orderId);

    assertNoSellOrder (orderId);
    assertNoVault (vman, 1);
  }

  /* ************************************************************************ */

  function test_acceptSellOrder () public
  {
    (uint256 orderId, bytes32 cpHash)
        = createCheckpointedOrder ("seller", "gold", 5, 10, seller);

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"5 gold from ctrl:1 to buyer\"}}}",
        address (vman));
    vm.prank (buyer);
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        orderId, 5, "buyer", cpHash));

    assertNoSellOrder (101);
    assertNoVault (vman, 1);

    assertEq (wchi.balanceOf (seller), 10);
    assertEq (wchi.balanceOf (buyer), BALANCE - 10);
  }

  function test_acceptSellOrderPartially () public
  {
    (uint256 orderId, bytes32 cpHash)
        = createCheckpointedOrder ("seller", "gold", 5, 10, seller);

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"2 gold from ctrl:1 to buyer\"}}}",
        address (vman));
    vm.prank (buyer);
    dem.acceptSellOrder (LimitSelling.AcceptedSellOrder (
        orderId, 2, "buyer", cpHash));

    assertSellOrder (101, 1, seller, "seller", "gold", 3, 6);
    assertVault (vman, 1, "seller", "gold", 3);

    assertEq (wchi.balanceOf (seller), 4);
    assertEq (wchi.balanceOf (buyer), BALANCE - 4);
  }

  function test_acceptSellOrderBatch () public
  {
    (uint256 orderId, bytes32 cpHash)
        = createCheckpointedOrder ("seller", "gold", 5, 10, seller);

    LimitSelling.AcceptedSellOrder[] memory orders
        = new LimitSelling.AcceptedSellOrder[] (2);
    orders[0] = LimitSelling.AcceptedSellOrder (orderId, 2, "buyer", cpHash);
    orders[1] = LimitSelling.AcceptedSellOrder (orderId, 3, "buyer", cpHash);

    ExpectedMove[] memory moves = new ExpectedMove[] (2);
    moves[0] = ExpectedMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"2 gold from ctrl:1 to buyer\"}}}",
        address (vman));
    moves[1] = ExpectedMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"3 gold from ctrl:1 to buyer\"}}}",
        address (vman));
    expectMoves (moves);
    vm.prank (buyer);
    dem.acceptSellOrders (orders);

    assertNoSellOrder (101);
    assertNoVault (vman, 1);

    assertEq (wchi.balanceOf (seller), 10);
    assertEq (wchi.balanceOf (buyer), BALANCE - 10);
  }

}
