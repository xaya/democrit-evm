// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./TradingTest.sol";
import "../src/Democrit.sol";

contract DemocritTest is TradingTest
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

  function test_checkSellOrders () public
  {
    uint256 tokenId = acc.tokenIdForName ("p", "buyer");

    vm.prank (seller);
    dem.createSellOrder ("seller", "gold", 5, 10);
    vm.prank (buyer);
    dem.createSellOrder ("buyer", "silver", 100, 1);
    vm.prank (buyer);
    acc.safeTransferFrom (buyer, seller, tokenId);

    uint256[] memory orderIds = new uint256[] (3);
    orderIds[0] = 101;
    orderIds[1] = 102;
    orderIds[2] = 103;
    Democrit.SellOrderStatus[] memory data = dem.checkSellOrders (orderIds);
    assertEq (data.length, 3);

    assertEq (data[0].exists, true);
    assertEq (data[0].valid, true);
    assertSellOrderData (data[0].order, 101, 1,
                         seller, "seller", "gold", 5, 10);

    assertEq (data[1].exists, true);
    assertEq (data[1].valid, false);
    assertSellOrderData (data[1].order, 102, 2,
                         buyer, "buyer", "silver", 100, 1);

    assertEq (data[2].exists, false);
    assertEq (data[2].valid, false);
    assertSellOrderNull (data[2].order);
  }

  function test_getTotalBuyCost () public view
  {
    assertEq (dem.getTotalBuyCost (100, 0, 0, 0), 0);
    assertEq (dem.getTotalBuyCost (100, 0, 0, 100), 0);
    assertEq (dem.getTotalBuyCost (100, 1000, 0, 20), 200);
    assertEq (dem.getTotalBuyCost (100, 1000, 10, 20), 220);
    assertEq (dem.getTotalBuyCost (100, 1001, 1, 50), 501 + 6);
    assertEq (dem.getTotalBuyCost (100, 1001, 100, 50), 501 * 2);
  }

  /**
   * @dev Tests the getMaxBuy function with the given inputs.  This verifies
   * that the output is the largest value for which the total cost does not
   * exceed the available amount (unless it is the full available amount
   * already).
   */
  function testMaxBuy (uint256 remaining, uint256 sats, uint64 relFee,
                       uint256 available) private view
  {
    uint256 maxBuy = dem.getMaxBuy (remaining, sats, relFee, available);
    assertLe (maxBuy, remaining);
    if (maxBuy == remaining)
      return;

    uint256 cost1 = dem.getTotalBuyCost (remaining, sats, relFee, maxBuy);
    assertLe (cost1, available);
    uint256 cost2 = dem.getTotalBuyCost (remaining, sats, relFee, maxBuy + 1);
    assertGt (cost2, available);
  }

  function test_getMaxBuy () public view
  {
    testMaxBuy (100, 0, 0, 10);
    testMaxBuy (100, 1000, 0, 20);
    testMaxBuy (100, 1000, 10, 20);
    testMaxBuy (100, 1000, 10, 1000000);
    testMaxBuy (100, 1001, 1, 20);
    testMaxBuy (100, 1001, 100, 20);
    testMaxBuy (1000027, 10, 1, 9);
    testMaxBuy (103, 1007, 2, 1020);

    /* Do some poor man's fuzz testing.  */
    for (uint64 fee = 0; fee <= 120; fee += 11)
      for (uint256 available = 0; available <= 1100; available += 173)
        {
          testMaxBuy (103, 1007, fee, available);
          testMaxBuy (1042999, 1007, fee, available);
        }
  }

  function test_checkBuyOrders () public
  {
    uint256 tokenId = acc.tokenIdForName ("p", "seller");

    setupWchi (seller);
    vm.prank (seller);
    wchi.approve (address (dem), type (uint256).max);

    vm.startPrank (pool);
    dem.createPool ("pool", "", "gold", 100, 10);
    dem.createPool ("pool", "", "gold", 100, 10);
    vm.stopPrank ();
    bytes32 cpHash = createCheckpoint ();

    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 100, 1, cpHash);
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 200, 2, cpHash);
    vm.prank (seller);
    dem.createBuyOrder ("seller", "gold", 10, 300, 1, cpHash);

    vm.prank (pool);
    dem.cancelPool (2);
    vm.prank (seller);
    acc.safeTransferFrom (seller, buyer, tokenId);

    uint256[] memory orderIds = new uint256[] (4);
    orderIds[0] = 101;
    orderIds[1] = 102;
    orderIds[2] = 103;
    orderIds[3] = 104;
    Democrit.BuyOrderStatus[] memory data = dem.checkBuyOrders (orderIds);
    assertEq (data.length, 4);

    assertEq (data[0].exists, true);
    assertEq (data[0].valid, true);
    assertBuyOrderData (data[0].order, 101, 1, "pool", 100, 10,
                        buyer, "buyer", "gold", 10, 100);

    assertEq (data[1].exists, false);
    assertEq (data[1].valid, false);
    assertBuyOrderNull (data[1].order);

    assertEq (data[2].exists, true);
    assertEq (data[2].valid, false);
    assertBuyOrderData (data[2].order, 103, 1, "pool", 100, 10,
                        seller, "seller", "gold", 10, 300);

    assertEq (data[3].exists, false);
    assertEq (data[3].valid, false);
    assertBuyOrderNull (data[3].order);
  }

  function test_availableWchiForBuyOrders () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 10);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 10, 100, 1, cpHash);

    setWchiBalance (buyer, 42);
    uint256[] memory orderIds = new uint256[] (1);
    orderIds[0] = 101;
    Democrit.BuyOrderStatus[] memory data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].availableSats, 42);

    vm.prank (buyer);
    wchi.approve (address (dem), 7);
    data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].availableSats, 7);

    setWchiBalance (buyer, 0);
    data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].availableSats, 0);
  }

  function test_maxBuyWithCheckedOrders () public
  {
    vm.prank (pool);
    dem.createPool ("pool", "", "gold", 100, 10);
    vm.prank (seller);
    dem.createSellDeposit ("seller", "gold", 100);
    bytes32 cpHash = createCheckpoint ();
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 90, 90, 1, cpHash);
    vm.prank (buyer);
    dem.createBuyOrder ("buyer", "gold", 100, 0, 1, cpHash);

    uint256[] memory orderIds = new uint256[] (2);
    orderIds[0] = 101;
    orderIds[1] = 102;

    /* Both orders can be taken in full, the limit is the available
       amount in the order.  */
    setWchiBalance (buyer, 1000);
    Democrit.BuyOrderStatus[] memory data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].maxBuy, 90);
    assertEq (data[1].maxBuy, 100);

    /* By taking part of the first order, we reduce the pool's available
       balance accordingly.  Then the second order's max buy will be determined
       by what is available in the pool.  */
    (LimitBuying.VaultCheck memory deposit, bytes memory signature)
        = signVaultCheck ("pool", 5, 2, cpHash);
    vm.prank (seller);
    dem.acceptBuyOrder (LimitBuying.AcceptedBuyOrder ({
      orderId: 101,
      amountSold: 50,
      deposit: deposit,
      signature: signature
    }));
    data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].maxBuy, 40);
    assertEq (data[1].maxBuy, 50);

    /* We reduce the WCHI balance of the buyer, this limits the maximum amount
       that can be bought.  */
    setWchiBalance (buyer, 22);
    data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].maxBuy, 20);
    assertEq (data[1].maxBuy, 50);

    /* Even at 0 WCHI, the order at price zero can be bought.  */
    setWchiBalance (buyer, 0);
    data = dem.checkBuyOrders (orderIds);
    assertEq (data[0].maxBuy, 0);
    assertEq (data[1].maxBuy, 50);
  }

}
