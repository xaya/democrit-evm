// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./TestConfig.sol";
import "./XayaEnvTest.sol";
import "../src/VaultManager.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import { Vm } from "forge-std/Vm.sol";

contract VaultManagerTest is XayaEnvTest
{

  address public immutable addr;
  TestConfig public immutable tc;

  VaultManager public vman;

  /**
   * @dev For getNumCheckpoints(), we read recorded logs and count the
   * CheckpointCreated events.  Since each call only returns logs from the
   * previous call onwards, we use this variable to track the previously
   * seen events, so that getNumCheckpoints() always returns the global, total
   * number of checkpoints since the test start.
   */
  uint private numCheckpoints;

  constructor ()
  {
    addr = vm.addr (2);
    vm.label (addr, "tester");

    tc = new TestConfig ();
  }

  function setUp () public override
  {
    XayaEnvTest.setUp ();
    vm.prank (addr);
    vman = new VaultManager (del, tc);

    setupWchi (supply);
    setupWchi (addr);

    vm.prank (supply);
    wchi.transfer (address (vman), 10**6);

    initialiseContract (vman, "ctrl");
    createFounder (vman, addr, "founder");

    vm.recordLogs ();
  }

  /**
   * @dev Helper function to return the number of CheckpointCreated events
   * that have been emitted since the test start.  This tracks checkpoints
   * cumulatively across multiple calls.
   */
  function getNumCheckpoints () internal returns (uint)
  {
    Vm.Log[] memory logs = vm.getRecordedLogs ();

    for (uint i = 0; i < logs.length; ++i)
      if (logs[i].topics[0] == VaultManager.CheckpointCreated.selector)
        ++numCheckpoints;

    return numCheckpoints;
  }

  function test_noVaultForOutOfIndex () public view
  {
    assertNoVault (vman, 100);
  }

  function test_indexZeroVault () public
  {
    vm.prank (addr);
    vman.createVault ("founder", "gold", 100);

    assertNoVault (vman, 0);
    assertVault (vman, 1, "founder", "gold", 100);
  }

  function test_movesForCreatingVault () public
  {
    ExpectedMove[] memory expected = new ExpectedMove[] (2);
    expected[0] = ExpectedMove ("ctrl",
        "{\"g\":{\"gid\":{\"create\": \"ctrl:1 for 200 gold of founder\"}}}",
        address (vman));
    expected[1] = ExpectedMove ("founder",
        "{\"g\":{\"gid\":{\"fund\":{\"ctrl:1\": \"with 200 gold by founder\"}}}}",
        address (del));

    expectMoves (expected);
    vm.prank (addr);
    vman.createVault ("founder", "gold", 200);
  }

  function test_createsVaultsInStorage () public
  {
    vm.startPrank (addr);
    vman.createVault ("founder", "gold", 10);
    vman.createVault ("founder", "silver", 20);

    assertEq (vman.getNumVaults (), 2);
    assertEq (vman.getNextVaultId (), 3);
    assertVault (vman, 1, "founder", "gold", 10);
    assertVault (vman, 2, "founder", "silver", 20);
  }

  function test_untradableAsset () public
  {
    vm.prank (addr);
    vm.expectRevert ("invalid asset for vault");
    vman.createVault ("founder", "iron", 5);
  }

  function test_zeroInitialBalance () public
  {
    vm.prank (addr);
    vm.expectRevert ("initial balance must be positive");
    vman.createVault ("founder", "gold", 0);
  }

  function test_uninitialised () public
  {
    vm.prank (addr);
    VaultManager vman2 = new VaultManager (del, tc);

    vm.prank (supply);
    wchi.transfer (address (vman2), 10**6);
    createFounder (vman2, addr, "founder2");

    vm.prank (addr);
    vm.expectRevert ("contract is not initialised");
    vman2.createVault ("founder2", "gold", 10);
  }

  function test_movesForSendingFromVault () public
  {
    vm.startPrank (addr);
    vman.createVault ("founder", "gold", 100);
    vman.createVault ("founder", "silver", 100);

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"10 gold from ctrl:1 to domob\"}}}",
        address (vman));
    vman.sendFromVault (1, "domob", 10);

    expectMove ("ctrl",
        "{\"g\":{\"gid\":{\"send\": \"20 silver from ctrl:2 to andy\"}}}",
        address (vman));
    vman.sendFromVault (2, "andy", 20);
  }

  function test_vaultUpdatesForSending () public
  {
    vm.startPrank (addr);
    vman.createVault ("founder", "gold", 100);
    vman.createVault ("founder", "silver", 100);

    vman.sendFromVault (1, "domob", 50);
    vman.sendFromVault (2, "andy", 20);
    vman.sendFromVault (1, "andy", 50);

    assertNoVault (vman, 1);
    assertVault (vman, 2, "founder", "silver", 80);
  }

  function test_sendingMoreThanExists () public
  {
    vm.startPrank (addr);
    vman.createVault ("founder", "gold", 100);
    vman.createVault ("founder", "silver", 100);

    vm.expectRevert ("trying to send zero amount");
    vman.sendFromVault (1, "domob", 0);

    vm.expectRevert ();
    vman.sendFromVault (100, "domob", 1);

    vman.sendFromVault (1, "domob", 100);
    vman.sendFromVault (2, "domob", 99);

    vm.expectRevert ("not enough funds in vault");
    vman.sendFromVault (1, "domob", 1);

    vm.expectRevert ("not enough funds in vault");
    vman.sendFromVault (2, "domob", 2);
  }

  function test_onlyOwnerCanCreateAndSend () public
  {
    address mallory = vm.addr (100);
    vm.label (mallory, "mallory");

    vm.prank (addr);
    vman.createVault ("founder", "gold", 100);

    vm.prank (mallory);
    vm.expectRevert ("Ownable: caller is not the owner");
    vman.createVault ("founder", "silver", 10);

    vm.prank (mallory);
    vm.expectRevert ("Ownable: caller is not the owner");
    vman.sendFromVault (1, "domob", 10);
  }

  function test_accountPermissions () public
  {
    address alice = vm.addr (101);
    address bob = vm.addr (102);
    address charlie = vm.addr (103);
    vm.label (alice, "alice");
    vm.label (bob, "bob");
    vm.label (charlie, "charlie");

    uint256 tokenId = acc.tokenIdForName ("p", "abc");
    vm.startPrank (addr);
    acc.register ("p", "abc");
    acc.setApprovalForAll (alice, true);
    acc.approve (bob, tokenId);
    vm.stopPrank ();

    setupWchi (charlie);
    vm.prank (charlie);
    acc.register ("g", "abc");

    assertTrue (vman.hasAccountPermission (addr, "abc"));
    assertTrue (vman.hasAccountPermission (alice, "abc"));
    assertTrue (vman.hasAccountPermission (bob, "abc"));
    assertFalse (vman.hasAccountPermission (charlie, "abc"));
  }

  function test_accountOwnership () public
  {
    address alice = vm.addr (101);
    address bob = vm.addr (102);
    vm.label (alice, "alice");
    vm.label (bob, "bob");

    setupWchi (alice);
    setupWchi (bob);

    vm.prank (alice);
    acc.register ("p", "abc");

    vm.prank (bob);
    acc.register ("g", "abc");

    assertEq (vman.getAccountAddress ("abc"), alice);
  }

  function test_createsCheckpoint () public
  {
    vm.prank (addr);
    vman.createVault ("founder", "gold", 10);
    uint256 blkNum = block.number;

    /* We need to advance to the next block before we can get the
       block hash using blockhash(...).  */
    vm.roll (blkNum + 1);

    bytes32 blkHash = blockhash (blkNum);
    assertFalse (vman.isCheckpoint (blkHash));

    expectMove ("ctrl",
        string (abi.encodePacked (
            "{\"g\":{\"gid\":{\"checkpoint\": \"",
            Strings.toString (blkNum), " ",
            Strings.toHexString (uint256 (blkHash)),
            " from ctrl\"}}}")),
        address (vman));

    vm.expectEmit (address (vman));
    emit VaultManager.CheckpointCreated (blkHash);

    vman.maybeCreateCheckpoint ();

    /* Advance again so we can use blockhash(...) on the next block.  */
    vm.roll (blkNum + 2);

    assertTrue (vman.isCheckpoint (blkHash));
    assertFalse (vman.isCheckpoint (blockhash (blkNum + 1)));
  }

  function test_checkpointsOnlyWhenNeeded () public
  {
    vman.maybeCreateCheckpoint ();
    assertEq (getNumCheckpoints (), 0);

    vm.prank (addr);
    vman.createVault ("founder", "gold", 10);
    assertEq (getNumCheckpoints (), 0);

    vm.roll (block.number + 1);
    vman.maybeCreateCheckpoint ();
    assertEq (getNumCheckpoints (), 1);

    vman.maybeCreateCheckpoint ();
    assertEq (getNumCheckpoints (), 1);
  }

  function test_autoCheckpointsMultipleOperationsInBlock () public
  {
    vm.startPrank (addr);
    vman.createVault ("founder", "gold", 10);
    assertEq (getNumCheckpoints (), 0);

    /* Perform two creates after each other in the next block.  This will
       checkpoint the vault created above, but only once, and also will not
       attempt to checkpoint the newly created vault.  */
    vm.roll (block.number + 1);
    vman.createVault ("founder", "silver", 5);
    vman.createVault ("founder", "silver", 10);
    assertEq (getNumCheckpoints (), 1);

    /* Perform a create and a spend-from-vault in the next block.  This
       will checkpoint the previous block (with the two vaults created
       there), but will not yet checkpoint the new one.  */
    vm.roll (block.number + 1);
    uint vaultId = vman.createVault ("founder", "copper", 10);
    vman.sendFromVault (vaultId, "domob", 5);
    assertEq (getNumCheckpoints (), 2);

    /* Do a single send, which will checkpoint the previous block as well.
       Then all checkpoints are done.  */
    vm.roll (block.number + 1);
    vman.sendFromVault (2, "domob", 1);
    assertEq (getNumCheckpoints (), 3);

    vm.roll (block.number + 1);
    vman.maybeCreateCheckpoint ();
    assertEq (getNumCheckpoints (), 3);
  }

}
