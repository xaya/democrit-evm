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

    /* Set up WCHI and approvals so we can send moves properly.  */
    await wchi.approve (acc.address, utils.maxUint256, {from: addr});
    await wchi.transfer (vm.address, 1000000, {from: addr});

    await utils.initialiseContract (vm, addr, "ctrl");
    await utils.createFounder (vm, addr, "founder");
  });

  it ("returns no vault for out-of-index", async () => {
    await utils.assertNoVault (vm, 100);
  });

  it ("sends moves for creating vaults correctly", async () => {
    await vm.create ("founder", "gold", 200, {from: addr});
    assert.deepEqual (await utils.getMoves (acc, 0), [
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
    assert.deepEqual (await utils.getMoves (acc, afterCreate), [
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

});
