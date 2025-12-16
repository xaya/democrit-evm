// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "../src/AccountHolder.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@xaya/eth-account-registry/src/XayaAccounts.sol";
import "@xaya/eth-account-registry/test/TestPolicy.sol";
import "@xaya/eth-account-registry/test/TestToken.sol";
import "@xaya/eth-delegator-contract/src/XayaDelegation.sol";

import { Test } from "forge-std/Test.sol";

/**
 * @dev This is a helper contract which contains a mapping.  It is able
 * to get and track the expected nonces included with Move events for
 * multiple names, and used by expectMoves().
 */
contract NonceTracker
{

  /** @dev The underlying XayaAccounts contract used.  */
  XayaAccounts private immutable acc;

  /**
   * @dev Expected next nonce per name, for names that we already have
   * processed.  Names not in here fall back to the real next nonce value
   * from XayaAccounts.
   */
  mapping (string => uint256) private nextNonceCache;

  constructor (XayaAccounts a)
  {
    acc = a;
  }

  /**
   * @dev Returns the expected next nonce for the given name.
   */
  function getNextNonce (string memory name)
      public view returns (uint256)
  {
    uint256 res = nextNonceCache[name];
    if (res > 0)
      return res;

    return acc.nextNonce (acc.tokenIdForName ("p", name));
  }

  /**
   * @dev Increments the expected next nonce for the given name (such as
   * after it sent a move).
   */
  function incrementNonce (string memory name) public
  {
    nextNonceCache[name] = getNextNonce (name) + 1;
  }

}

/**
 * @dev Test fixture that sets up a basic Xaya environment (WCHI, accounts
 * contract, move delegation).  This is the basis for most Democrit tests.
 */
contract XayaEnvTest is Test
{

  address public immutable supply;

  /* The basic Xaya environment contracts.  */
  IERC20 public wchi;
  XayaAccounts public acc;
  XayaDelegation public del;

  constructor ()
  {
    supply = vm.addr (1);
    vm.label (supply, "supply");
  }

  function setUp () public virtual
  {
    (wchi, acc, del) = setupXaya (supply);
  }

  /**
   * @dev Sets up the basic contract environment including WCHI, XayaAccounts
   * with a test policy, and XayaDelegation.  The provided address is used to
   * construct all of them from, which effectively means that it will hold the
   * initial WCHI supply and also be owner of the contracts where applicable.
   */
  function setupXaya (address deployer)
      internal returns (IERC20 w, XayaAccounts a, XayaDelegation d)
  {
    vm.startPrank (deployer);
    w = new TestToken (10**20);
    IXayaPolicy policy = new TestPolicy ();
    a = new XayaAccounts (w, policy);
    d = new XayaDelegation (a, address (0));
    vm.stopPrank ();
  }

  /**
   * @dev Transfers some WCHI from supply to the given address and approves
   * WCHI on the accounts registry.  This is basically the setup required to
   * register names with the given address.
   */
  function setupWchi (address addr) internal
  {
    vm.prank (supply);
    wchi.transfer (addr, 10**6);
    vm.prank (addr);
    wchi.approve (address (acc), type (uint256).max);
  }

  /**
   * @dev Initialises the AccountHolder (or subcontract) by registering
   * the given name and transferring it to it.
   */
  function initialiseContract (AccountHolder ah, string memory name)
      internal
  {
    assertEq (address (acc), address (ah.accountRegistry ()));

    uint256 tokenId = acc.tokenIdForName ("p", name);

    vm.startPrank (supply);
    acc.register ("p", name);
    acc.safeTransferFrom (supply, address (ah), tokenId);
    vm.stopPrank ();

    assertTrue (ah.initialised ());
  }

  /**
   * @dev Data about an expected move.
   */
  struct ExpectedMove
  {
    string name;
    string mv;
    address mover;
  }

  /**
   * @dev Expects the given moves to be sent (via vm.expectEmit).
   */
  function expectMoves (ExpectedMove[] memory expected) internal
  {
    /* We need to first calculate all the data and (in particular) nonces,
       and then do the expectEmit calls so they apply to the final call.  */
    NonceTracker tracker = new NonceTracker (acc);
    uint256[] memory tokenIds = new uint256[] (expected.length);
    uint256[] memory nonces = new uint256[] (expected.length);

    for (uint i = 0; i < expected.length; ++i)
      {
        tokenIds[i] = acc.tokenIdForName ("p", expected[i].name);
        nonces[i] = tracker.getNextNonce (expected[i].name);
        tracker.incrementNonce (expected[i].name);
      }

    for (uint i = 0; i < expected.length; ++i)
      {
        vm.expectEmit (address (acc));
        emit IXayaAccounts.Move ("p", expected[i].name, expected[i].mv,
                                 tokenIds[i], nonces[i],
                                 expected[i].mover, 0, address (0));
      }
  }

  /**
   * @dev Expects that a single move is sent.
   */
  function expectMove (string memory name, string memory mv, address mover)
      internal
  {
    ExpectedMove[] memory expected = new ExpectedMove[] (1);
    expected[0] = ExpectedMove (name, mv, mover);
    expectMoves (expected);
  }

}
