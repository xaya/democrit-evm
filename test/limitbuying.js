// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const TestConfig = artifacts.require ("TestConfig");

/** The initial balance held by the buyer in WCHI sats.  */
const BALANCE = 1000000;

contract ("LimitBuying", accounts => {
  const supply = accounts[0];
  const buyer = accounts[1];
  const seller = accounts[2];
  const pool = accounts[3];

  let tc;
  before (async () => {
    tc = await TestConfig.new ();
  });

  let wchi, acc, del, vm, dem;
  beforeEach (async () => {
    ({wchi, acc, del, vm, dem}
        = await utils.setupTradingTest (tc, supply, buyer, seller, BALANCE));
    await utils.setupPoolOperator (dem, supply, pool, "pool");
  });

  /**
   * Expects that a pool with the given specifics exists.
   */
  async function assertPool (vaultId, operator, asset, amount, fee)
  {
    const data = await dem.getPool (vaultId);
    assert.equal (data["vaultId"], vaultId);
    assert.equal (data["operator"], operator);
    assert.equal (data["asset"], asset);
    assert.equal (data["amount"], amount);
    assert.equal (data["relFee"], fee);
  }

  /**
   * Expects that no pool with the given ID exists.
   */
  async function assertNoPool (vaultId)
  {
    const data = await dem.getPool (vaultId);
    assert.equal (data["vaultId"], "0");
    assert.equal (data["operator"], "");
    assert.equal (data["asset"], "");
    assert.equal (data["amount"], "0");
    assert.equal (data["relFee"], "0");
  }

  /* ************************************************************************ */

  it ("computes the pool fee correctly", async () => {
    await truffleAssert.reverts (dem.getPoolFee (100, utils.maxUint256),
                                 "revert");
    assert.equal (await dem.getPoolFee (0, 100), 0);
    assert.equal (await dem.getPoolFee (100, 0), 0);
    assert.equal (await dem.getPoolFee (10, 256), 26);
    assert.equal (await dem.getPoolFee (1, 1), 1);
    assert.equal (await dem.getPoolFee (1, 100), 1);
    const large = web3.utils.toBN ("2").pow (web3.utils.toBN ("128"));
    assert.equal ((await dem.getPoolFee (100, large)).toString (),
                  large.toString ());
  });

  it ("returns nothing for a non-existing pool", async () => {
    assertNoPool (123);
  });

  it ("verifies asset, amount and fee when creating a pool", async () => {
    await truffleAssert.reverts (
        dem.createPool ("pool", "", "gold", 0, 0, {from: pool}),
        "non-zero amount required");
    await truffleAssert.reverts (
        dem.createPool ("pool", "", "invalid", 1, 1, {from: pool}),
        "invalid asset");
    await truffleAssert.reverts (
        dem.createPool ("pool", "", "gold", 1, 11, {from: pool}),
        "fee too high");
  });

  it ("verifies the sender address's permission", async () => {
    await truffleAssert.reverts (
        dem.createPool ("pool", "", "gold", 1, 1, {from: seller}),
        "no permission");
  });

  it ("creates trading pools correctly", async () => {
    await dem.createPool ("pool", "", "gold", 5, 0, {from: pool});
    await dem.createPool ("pool", "", "silver", 100, 10, {from: pool});

    await utils.assertVault (vm, 1, "pool", "gold", 5);
    await utils.assertVault (vm, 2, "pool", "silver", 100);

    await assertPool (1, "pool", "gold", 5, 0);
    await assertPool (2, "pool", "silver", 100, 10);
  });

  it ("fails to cancel a non-existing pool", async () => {
    await truffleAssert.reverts (dem.cancelPool (1, {from: pool}),
                                 "does not exist");
  });

  it ("verifies permission when cancelling a pool", async () => {
    await dem.createPool ("pool", "", "gold", 5, 0, {from: pool});
    await truffleAssert.reverts (dem.cancelPool (1, {from: buyer}),
                                 "no permission");
  });

  it ("cancels a trading pool correctly", async () => {
    await dem.createPool ("pool", "", "gold", 5, 10, {from: pool});
    await dem.createPool ("pool", "", "silver", 100, 1, {from: pool});

    const afterCreate = await web3.eth.getBlockNumber () + 1;
    await dem.cancelPool (1, {from: pool});
    assert.deepEqual (
      utils.ignoreCheckpoints (await utils.getMoves (acc, afterCreate)), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to pool"
      }}}],
    ]);

    await assertNoPool (1);
    await utils.assertNoVault (vm, 1);

    await assertPool (2, "pool", "silver", 100, 1);
    await utils.assertVault (vm, 2, "pool", "silver", 100);
  });

  /* ************************************************************************ */

});
