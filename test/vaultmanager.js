// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const VaultManagerTestHelper = artifacts.require ("VaultManagerTestHelper");
const TestConfig = artifacts.require ("TestConfig");

contract ("VaultManager", accounts => {
  let addr = accounts[0];

  let tc;
  before (async () => {
    tc = await TestConfig.new ();
  });

  let wchi, acc, del, ah;
  beforeEach (async () => {
    ({wchi, acc, del} = await utils.xayaEnvironment (addr));
    vm = await VaultManagerTestHelper.new (del.address, tc.address);
    await utils.setupWchi (acc, addr, addr);
    await wchi.transfer (vm.address, 1000000, {from: addr});

    await utils.initialiseContract (vm, addr, "ctrl");
    await utils.createFounder (vm, addr, "founder");
  });

  /**
   * Helper function to return the number of checkpoints created.
   * We use this to test the situations where we expect that the
   * auto-checkpointing works as it should.
   */
  async function getNumCheckpoints ()
  {
    const events
        = await vm.getPastEvents ("CheckpointCreated",
                                  {fromBlock: 0, toBlock: "latest"});
    return events.length;
  }

  it ("returns no vault for out-of-index", async () => {
    await utils.assertNoVault (vm, 100);
  });

  it ("sends moves for creating vaults correctly", async () => {
    await vm.create ("founder", "gold", 200, {from: addr});
    assert.deepEqual (utils.ignoreCheckpoints (await utils.getMoves (acc, 0)), [
      ["ctrl", {"g": {"gid": {
        "create": "ctrl:0 for 200 gold of founder"
      }}}],
      ["founder", {"g": {"gid": {
        "fund": {"ctrl:0": "with 200 gold by founder"}
      }}}],
    ]);
  });

  it ("creates vaults in the storage correctly", async () => {
    await vm.create ("founder", "gold", 10, {from: addr});
    await vm.create ("founder", "silver", 20, {from: addr});

    assert.equal (await vm.getNumVaults (), 2);
    utils.assertVault (vm, 0, "founder", "gold", 10);
    utils.assertVault (vm, 1, "founder", "silver", 20);
  });

  it ("does not allow untradable assets", async () => {
    await truffleAssert.reverts (
        vm.create ("founder", "iron", 5, {from: addr}),
        "invalid asset");
  });

  it ("does not allow zero initial balance", async () => {
    await truffleAssert.reverts (
        vm.create ("founder", "gold", 0, {from: addr}),
        "initial balance must be positive");
  });

  it ("creates the right moves for sending from vaults", async () => {
    await vm.create ("founder", "gold", 100, {from: addr});
    await vm.create ("founder", "silver", 100, {from: addr});
    const afterCreate = await web3.eth.getBlockNumber () + 1;
    await vm.send (0, "domob", 10, {from: addr});
    await vm.send (1, "andy", 20, {from: addr});
    assert.deepEqual (
      utils.ignoreCheckpoints (await utils.getMoves (acc, afterCreate)), [
      ["ctrl", {"g": {"gid": {
        "send": "10 gold from ctrl:0 to domob"
      }}}],
      ["ctrl", {"g": {"gid": {
        "send": "20 silver from ctrl:1 to andy"
      }}}],
    ]);
  });

  it ("updates vaults correctly for sending", async () => {
    await vm.create ("founder", "gold", 100, {from: addr});
    await vm.create ("founder", "silver", 100, {from: addr});

    await vm.send (0, "domob", 50, {from: addr});
    await vm.send (1, "andy", 20, {from: addr});
    await vm.send (0, "andy", 50, {from: addr});

    utils.assertNoVault (vm, 0);
    utils.assertVault (vm, 1, "founder", "silver", 80);
  });

  it ("fails when sending more from a vault than exists", async () => {
    await vm.create ("founder", "gold", 100, {from: addr});
    await vm.create ("founder", "silver", 100, {from: addr});

    await truffleAssert.reverts (
        vm.send (0, "domob", 0, {from: addr}),
        "trying to send zero amount");
    await truffleAssert.reverts (
        vm.send (100, "domob", 1, {from: addr}),
        "revert");

    await vm.send (0, "domob", 100, {from: addr});
    await vm.send (1, "domob", 99, {from: addr});

    await truffleAssert.reverts (
        vm.send (0, "domob", 1, {from: addr}),
        "not enough funds");
    await truffleAssert.reverts (
        vm.send (1, "domob", 2, {from: addr}),
        "not enough funds");
  });

  it ("checks account permissions correctly", async () => {
    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];

    const tokenId = await acc.tokenIdForName ("p", "abc");
    await acc.register ("p", "abc", {from: addr});
    await acc.setApprovalForAll (alice, true, {from: addr});
    await acc.approve (bob, tokenId, {from: addr});

    await utils.setupWchi (acc, addr, charlie);
    await acc.register ("g", "abc", {from: charlie});

    assert.isTrue (await vm.hasAccountPermission (addr, "abc"));
    assert.isTrue (await vm.hasAccountPermission (alice, "abc"));
    assert.isTrue (await vm.hasAccountPermission (bob, "abc"));
    assert.isFalse (await vm.hasAccountPermission (charlie, "abc"));
  });

  it ("returns account ownership", async () => {
    const alice = accounts[1];
    const bob = accounts[2];

    await utils.setupWchi (acc, addr, alice);
    await utils.setupWchi (acc, addr, bob);

    await acc.register ("p", "abc", {from: alice});
    await acc.register ("g", "abc", {from: bob});

    assert.equal (await vm.getAccountAddress ("abc"), alice);
  });

  it ("creates a checkpoint correctly", async () => {
    await vm.create ("founder", "gold", 10, {from: addr});
    const blk = await web3.eth.getBlock ("latest");

    assert.equal (await getNumCheckpoints (), 0);
    assert.isFalse (await vm.isCheckpoint (blk["hash"]));

    await vm.maybeCreateCheckpoint ();
    const blk2 = await web3.eth.getBlock ("latest");

    assert.deepEqual (await utils.getMoves (acc, blk2["number"]), [
      ["ctrl", {"g": {"gid": {
        "checkpoint": blk["number"].toString () + " " + blk["hash"]
                        + " from ctrl"
      }}}],
    ]);
    assert.equal (await getNumCheckpoints (), 1);
    assert.isTrue (await vm.isCheckpoint (blk["hash"]));
    assert.isFalse (await vm.isCheckpoint (blk2["hash"]));
  });

  it ("creates checkpoints only when needed", async () => {
    await vm.maybeCreateCheckpoint ();
    assert.equal (await getNumCheckpoints (), 0);
    await vm.create ("founder", "gold", 10, {from: addr});
    assert.equal (await getNumCheckpoints (), 0);
    await vm.maybeCreateCheckpoint ();
    assert.equal (await getNumCheckpoints (), 1);
    await vm.maybeCreateCheckpoint ();
    assert.equal (await getNumCheckpoints (), 1);
  });

  it ("auto-checkpoints multiple operations in a block correctly", async () => {
    await vm.create ("founder", "gold", 10, {from: addr});
    assert.equal (await getNumCheckpoints (), 0);

    /* Perform two creates after each other in the next block.  This will
       checkpoint the vault created above, but only once, and also will not
       attempt to checkpoint the newly created vault.  */
    await vm.createMany ("founder", "silver", [5, 10]);
    assert.equal (await getNumCheckpoints (), 1);

    /* Perform a create and a spend-from-vault in the next block.  This
       will checkpoint the previous block (with the two vaults created
       there), but will not yet checkpoint the new one.  */
    await vm.createAndSend ("founder", "copper", 10, "domob", 5);
    assert.equal (await getNumCheckpoints (), 2);

    /* Do a single send, which will checkpoint the previous block as well.
       Then all checkpoints are done.  */
    await vm.send (1, "domob", 1);
    assert.equal (await getNumCheckpoints (), 3);

    await vm.maybeCreateCheckpoint ();
    assert.equal (await getNumCheckpoints (), 3);
  });

});
