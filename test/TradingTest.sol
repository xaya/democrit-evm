// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./DemocritTestHelper.sol";
import "./TestConfig.sol";
import "./XayaEnvTest.sol";
import "../src/VaultManager.sol";

/**
 * @dev Test fixture that sets up a full trading environment for testing
 * the Democrit contracts.
 */
contract TradingTest is XayaEnvTest
{

  /** @dev The initial balance held by the seller in sats.  */
  uint public constant BALANCE = 1000000;

  address public immutable buyer;
  address public immutable seller;

  TestConfig private immutable tc;

  VaultManager public vman;
  DemocritTestHelper public dem;

  constructor ()
  {
    buyer = vm.addr (2);
    seller = vm.addr (3);

    vm.label (buyer, "buyer");
    vm.label (seller, "seller");

    tc = new TestConfig ();
  }

  function setUp () public override
  {
    XayaEnvTest.setUp ();

    vm.startPrank (supply);
    vman = new VaultManager (del, tc);
    dem = new DemocritTestHelper (vman, 101);
    vman.transferOwnership (address (dem));
    vm.stopPrank ();

    setupWchi (supply);
    initialiseContract (vman, "ctrl");
    vm.prank (supply);
    wchi.transfer (address (vman), 1000000);

    setupWchi (buyer);
    setupWchi (seller);
    createFounder (vman, buyer, "buyer");
    createFounder (vman, seller, "seller");
    setWchiBalance (seller, 0);
    setWchiBalance (buyer, BALANCE);
    vm.prank (buyer);
    wchi.approve (address (dem), type (uint256).max);
  }

  /**
   * @dev Sets the WCHI balance of a given account to the specified amount.
   *
   * For this, we transfer to/from the supply account.
   */
  function setWchiBalance (address addr, uint balance) internal
  {
    uint current = wchi.balanceOf (addr);
    if (current > balance)
      {
        vm.prank (addr);
        wchi.transfer (supply, current - balance);
      }
    else if (current < balance)
      {
        vm.prank (supply);
        wchi.transfer (addr, balance - current);
      }
    assertEq (wchi.balanceOf (addr), balance);
  }

  /**
   * @dev Creates a checkpoint in the contract and returns its hash.
   */
  function createCheckpoint () internal returns (bytes32)
  {
    uint256 height = block.number;
    vm.roll (height + 1);
    vman.maybeCreateCheckpoint ();
    return blockhash (height);
  }

  /**
   * @dev Asserts that the given sell order data matches the null data,
   * i.e. a sell order that doesn't exist.
   */
  function assertSellOrderNull (LimitSelling.CompleteSellOrder memory data)
      internal pure
  {
    assertEq (data.orderId, 0);
    assertEq (data.vaultId, 0);
    assertEq (data.creator, address (0));
    assertEq (data.seller, "");
    assertEq (data.asset, "");
    assertEq (data.remainingAmount, 0);
    assertEq (data.totalSats, 0);
  }

  /**
   * @dev Asserts that the given sell order matches the expected data.
   */
  function assertSellOrderData (LimitSelling.CompleteSellOrder memory data,
                                uint256 orderId, uint256 vaultId,
                                address creator, string memory sel,
                                string memory asset,
                                uint256 amount, uint256 sats)
      internal pure
  {
    assertEq (data.orderId, orderId);
    assertEq (data.vaultId, vaultId);
    assertEq (data.creator, creator);
    assertEq (data.seller, sel);
    assertEq (data.asset, asset);
    assertEq (data.remainingAmount, amount);
    assertEq (data.totalSats, sats);
  }

}
