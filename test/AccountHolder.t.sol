// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./XayaEnvTest.sol";
import "../src/AccountHolder.sol";

/**
 * @dev Basic subclass of AccountHolder, which exposes sendMove
 * to the unit tests.
 */
contract AccountHolderTestHelper is AccountHolder
{

  constructor (XayaDelegation del)
    AccountHolder(del)
  {}

  function sendMoveFromTest (string memory mv) public
  {
    sendMove (mv);
  }

}

contract AccountHolderTest is XayaEnvTest
{

  address public immutable addr;

  AccountHolderTestHelper public ah;

  constructor ()
  {
    addr = vm.addr (2);
    vm.label (addr, "tester");
  }

  function setUp () public override
  {
    XayaEnvTest.setUp ();
    ah = new AccountHolderTestHelper (del);
    setupWchi (supply);
    setupWchi (addr);

    /* Transfer some WCHI to the AccountHolder, so it can actually
       pay for moves.  */
    vm.prank (supply);
    wchi.transfer (address (ah), 10**6);
  }

  function test_unexpectedNftTransfer () public
  {
    (, XayaAccounts acc2, ) = setupXaya (supply);
    vm.startPrank (addr);

    uint256 tokenId1 = acc.tokenIdForName ("g", "x");
    acc.register ("g", "x");

    uint256 tokenId2 = acc2.tokenIdForName ("p", "y");
    acc2.register ("p", "y");

    vm.expectRevert ("only Xaya accounts can be received");
    acc.safeTransferFrom (addr, address (ah), tokenId1);

    vm.expectRevert ("only Xaya names can be received");
    acc2.safeTransferFrom (addr, address (ah), tokenId2);
  }

  function test_validInitialisation () public
  {
    vm.startPrank (addr);
    uint256 tokenId = acc.tokenIdForName ("p", "foo");
    acc.register ("p", "foo");

    assertFalse (ah.initialised ());
    acc.safeTransferFrom (addr, address (ah), tokenId);

    assertTrue (ah.initialised ());
    assertEq (ah.account (), "foo");
  }

  function test_duplicateInitialisation () public
  {
    initialiseContract (ah, "right");

    vm.startPrank (addr);
    uint256 tokenId = acc.tokenIdForName ("p", "wrong");
    acc.register ("p", "wrong");

    vm.expectRevert ("contract is already initialised");
    acc.safeTransferFrom (addr, address (ah), tokenId);

    assertTrue (ah.initialised ());
    assertEq (ah.account (), "right");
  }

  function test_moves () public
  {
    vm.expectRevert ("contract is not initialised");
    ah.sendMoveFromTest ("move");
    initialiseContract (ah, "foo");

    expectMove ("foo", "some", address (ah));
    ah.sendMoveFromTest ("some");
    expectMove ("foo", "moves", address (ah));
    ah.sendMoveFromTest ("moves");
  }

}
