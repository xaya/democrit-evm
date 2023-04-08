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

  /* ************************************************************************ */

  /**
   * Asserts that the given JSON data corresponds to a pool with the
   * given data fields.
   */
  function assertPoolData (data, vaultId, operator, asset, amount, fee)
  {
    assert.equal (data["vaultId"], vaultId);
    assert.equal (data["operator"], operator);
    assert.equal (data["asset"], asset);
    assert.equal (data["amount"], amount);
    assert.equal (data["relFee"], fee);
  }

  /**
   * Expects that a pool with the given specifics exists.
   */
  async function assertPool (vaultId, operator, asset, amount, fee)
  {
    const data = await dem.getPool (vaultId);
    assertPoolData (data, vaultId, operator, asset, amount, fee);
  }

  /**
   * Asserts that the given JSON data corresponds to a pool that does
   * not exist (null data).
   */
  function assertPoolNull (data)
  {
    assert.equal (data["vaultId"], "0");
    assert.equal (data["operator"], "");
    assert.equal (data["asset"], "");
    assert.equal (data["amount"], "0");
    assert.equal (data["relFee"], "0");
  }

  /**
   * Expects that no pool with the given ID exists.
   */
  async function assertNoPool (vaultId)
  {
    const data = await dem.getPool (vaultId);
    assertPoolNull (data);
  }

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

  it ("verifies the sender address's permission for a pool", async () => {
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

  /**
   * Expects that a sell deposit with the given specifics exists.
   */
  async function assertDeposit (vaultId, owner, asset, amount)
  {
    const data = await dem.getSellDeposit (vaultId);
    assert.equal (data["vaultId"], vaultId);
    assert.equal (data["owner"], owner);
    assert.equal (data["asset"], asset);
    assert.equal (data["amount"], amount);
  }

  /**
   * Expects that no sell deposit with the given ID exists.
   */
  async function assertNoDeposit (vaultId)
  {
    const data = await dem.getSellDeposit (vaultId);
    assert.equal (data["vaultId"], "0");
    assert.equal (data["owner"], "");
    assert.equal (data["asset"], "");
    assert.equal (data["amount"], "0");
  }

  it ("returns nothing for a non-existing sell deposit", async () => {
    assertNoDeposit (123);
  });

  it ("verifies asset and amount when creating a deposit", async () => {
    await truffleAssert.reverts (
        dem.createSellDeposit ("seller", "gold", 0, {from: seller}),
        "non-zero amount required");
    await truffleAssert.reverts (
        dem.createSellDeposit ("seller", "invalid", 1, {from: seller}),
        "invalid asset");
  });

  it ("verifies the sender address's permission for a deposit", async () => {
    await truffleAssert.reverts (
        dem.createSellDeposit ("seller", "gold", 1, {from: buyer}),
        "no permission");
  });

  it ("creates a sell deposit correctly", async () => {
    await dem.createSellDeposit ("seller", "gold", 5, {from: seller});

    await utils.assertVault (vm, 1, "seller", "gold", 5);
    await assertDeposit (1, "seller", "gold", 5);
  });

  it ("fails to cancel a non-existing deposit", async () => {
    await truffleAssert.reverts (dem.cancelSellDeposit (1, {from: seller}),
                                 "does not exist");
  });

  it ("verifies permission when cancelling a deposit", async () => {
    await dem.createSellDeposit ("seller", "gold", 5, {from: seller});
    await truffleAssert.reverts (dem.cancelSellDeposit (1, {from: buyer}),
                                 "no permission");
  });

  it ("cancels a sell deposit correctly", async () => {
    await dem.createSellDeposit ("seller", "gold", 5, {from: seller});
    await dem.createSellDeposit ("seller", "silver", 100, {from: seller});

    const afterCreate = await web3.eth.getBlockNumber () + 1;
    await dem.cancelSellDeposit (1, {from: seller});
    assert.deepEqual (
      utils.ignoreCheckpoints (await utils.getMoves (acc, afterCreate)), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to seller"
      }}}],
    ]);

    await assertNoDeposit (1);
    await utils.assertNoVault (vm, 1);

    await assertDeposit (2, "seller", "silver", 100);
    await utils.assertVault (vm, 2, "seller", "silver", 100);
  });

  /* ************************************************************************ */

  /**
   * Expects that a buy order with the given specifics exists.
   */
  async function assertBuyOrder (orderId, poolId,
                                 poolOperator, poolAmount, poolFee,
                                 creator, buyer, asset,
                                 remainingAmount, totalSats)
  {
    const data = await dem.getBuyOrder (orderId);
    assert.equal (data["orderId"], orderId);
    assert.equal (data["poolId"], poolId);
    assertPoolData (data["poolData"], poolId, poolOperator,
                    asset, poolAmount, poolFee);
    assert.equal (data["creator"], creator);
    assert.equal (data["buyer"], buyer);
    assert.equal (data["asset"], asset);
    assert.equal (data["remainingAmount"], remainingAmount);
    assert.equal (data["totalSats"], totalSats);
  }

  /**
   * Expects that no buy order with the given ID exists.
   */
  async function assertNoBuyOrder (orderId)
  {
    const data = await dem.getBuyOrder (orderId);
    assert.equal (data["orderId"], "0");
    assert.equal (data["poolId"], "0");
    assertPoolNull (data["poolData"]);
    assert.equal (data["creator"], utils.nullAddress);
    assert.equal (data["buyer"], "");
    assert.equal (data["asset"], "");
    assert.equal (data["remainingAmount"], "0");
    assert.equal (data["totalSats"], "0");
  }

  /**
   * Creates a trading pool and checkpoints it.  This uses the pool
   * address and "pool" operator name.
   */
  async function createCheckpointedPool (asset, amount, fee)
  {
    const poolId = (await vm.getNextVaultId ()).toNumber ();
    await dem.createPool ("pool", "", asset, amount, fee, {from: pool});
    const cpHash = await utils.createCheckpoint (vm);
    return {poolId, cpHash};
  }

  it ("returns nothing for a non-existing buy order", async () => {
    await assertNoBuyOrder (123);
  });

  it ("verifies amount and sender permissions when creating a buy order",
      async () => {
    const {poolId, cpHash} = await createCheckpointedPool ("gold", 10, 1);

    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 0, 10, poolId, cpHash,
                            {from: buyer}),
        "non-zero amount required");
    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 1, 10, poolId, cpHash,
                            {from: seller}),
        "no permission");
  });

  it ("verifies the chosen pool when creating a buy order", async () => {
    const noCheckpoint = await utils.getBestBlock ();
    const {poolId, cpHash} = await createCheckpointedPool ("gold", 10, 1);

    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 11, 10, 123, cpHash,
                            {from: buyer}),
        "insufficient balance");
    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 11, 10, poolId, cpHash,
                            {from: buyer}),
        "insufficient balance");
    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "silver", 3, 10, poolId, cpHash,
                            {from: buyer}),
        "asset mismatch");
    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 3, 10, poolId, noCheckpoint,
                            {from: buyer}),
        "checkpoint is invalid");
  });

  it ("verifies the WCHI balance and allowance", async () => {
    await dem.createPool ("pool", "", "gold", 100, 10, {from: pool});
    await dem.createPool ("pool", "", "gold", 100, 0, {from: pool});
    const cpHash = await utils.createCheckpoint (vm);

    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 1, BALANCE - 1, 1, cpHash,
                            {from: buyer}),
        "insufficient WCHI balance");
    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 1, BALANCE + 1, 2, cpHash,
                            {from: buyer}),
        "insufficient WCHI balance");

    await wchi.approve (dem.address, BALANCE - 1, {from: buyer});
    await truffleAssert.reverts (
        dem.createBuyOrder ("buyer", "gold", 1, BALANCE, 2, cpHash,
                            {from: buyer}),
        "insufficient WCHI allowance");
  });

  it ("creates a buy order correctly", async () => {
    const {poolId, cpHash} = await createCheckpointedPool ("gold", 100, 0);
    await dem.createBuyOrder ("buyer", "gold", 100, BALANCE, poolId, cpHash,
                              {from: buyer});

    await assertBuyOrder (101, poolId, "pool", 100, 0,
                          buyer, "buyer", "gold", 100, BALANCE);
    /* No WCHI is actually moved by creating the order.  */
    assert.equal ((await wchi.balanceOf (buyer)).toNumber (), BALANCE);
  });

  it ("returns nothing for a buy order with cancelled pool", async () => {
    const {poolId, cpHash} = await createCheckpointedPool ("gold", 100, 0);
    await dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash,
                              {from: buyer});

    await dem.cancelPool (poolId, {from: pool});
    await assertNoBuyOrder (101);
  });

  it ("fails to cancel a non-existing buy order", async () => {
    await truffleAssert.reverts (dem.cancelBuyOrder (123, {from: buyer}),
                                 "does not exist");
  });

  it ("checks permissions when cancelling a buy order", async () => {
    const {poolId, cpHash} = await createCheckpointedPool ("gold", 100, 0);
    await dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash,
                              {from: buyer});

    await truffleAssert.reverts (dem.cancelBuyOrder (101, {from: pool}),
                                 "no permission");
  });

  it ("cancels a buy order correctly", async () => {
    const {poolId, cpHash} = await createCheckpointedPool ("gold", 100, 0);
    await dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash,
                              {from: buyer});
    await dem.createBuyOrder ("buyer", "gold", 100, 10, poolId, cpHash,
                              {from: buyer});

    await dem.cancelBuyOrder (101, {from: buyer});
    await assertNoBuyOrder (101);
    await assertBuyOrder (102, poolId, "pool", 100, 0,
                          buyer, "buyer", "gold", 100, 10);
    await truffleAssert.reverts (dem.cancelBuyOrder (101, {from: buyer}),
                                 "does not exist");

    /* Even if the pool is cancelled and the buy order "hidden", it can be
       cancelled.  But cancelling again will fail, as this is a "real" check
       whether or not the data exists in storage.  */
    await dem.cancelPool (poolId, {from: pool});
    await assertNoBuyOrder (102);
    await dem.cancelBuyOrder (102, {from: buyer});
    await truffleAssert.reverts (dem.cancelBuyOrder (102, {from: buyer}),
                                 "does not exist");
  });

  /* ************************************************************************ */

  it ("correctly distinguishes orders, trading pools and sell deposits",
      async () => {
    await dem.setNextOrderId (1);

    await dem.createSellOrder ("seller", "gold", 1, 10, {from: seller});
    await dem.createPool ("pool", "", "silver", 2, 10, {from: pool});
    await dem.createSellDeposit ("seller", "copper", 3, {from: seller});
    const cpHash = await utils.createCheckpoint (vm);
    await dem.createBuyOrder ("buyer", "silver", 1, 1, 2, cpHash,
                              {from: buyer});

    await utils.assertVault (vm, 1, "seller", "gold", 1);
    await utils.assertVault (vm, 2, "pool", "silver", 2);
    await utils.assertVault (vm, 3, "seller", "copper", 3);

    utils.assertSellOrderData (await dem.getSellOrder (1), 1, 1, seller,
                               "seller", "gold", 1, 10);
    await assertNoPool (1);
    await assertNoDeposit (1);
    await assertNoBuyOrder (1);

    utils.assertSellOrderNull (await dem.getSellOrder (2));
    await assertPool (2, "pool", "silver", 2, 10);
    await assertNoDeposit (2);
    /* The buy order also has ID 2, since orders have their own ID series
       and it also does not imply a vault.  */
    await assertBuyOrder (2, 2, "pool", 2, 10,
                          buyer, "buyer", "silver", 1, 1);

    utils.assertSellOrderNull (await dem.getSellOrder (3));
    await assertNoPool (3);
    await assertDeposit (3, "seller", "copper", 3);
    await assertNoBuyOrder (3);

    await truffleAssert.reverts (dem.cancelSellOrder (2, {from: seller}),
                                 "does not exist");
    await truffleAssert.reverts (dem.cancelSellOrder (3, {from: seller}),
                                 "does not exist");

    await truffleAssert.reverts (dem.cancelPool (1, {from: pool}),
                                 "does not exist");
    await truffleAssert.reverts (dem.cancelPool (3, {from: pool}),
                                 "does not exist");

    await truffleAssert.reverts (dem.cancelSellDeposit (1, {from: seller}),
                                 "does not exist");
    await truffleAssert.reverts (dem.cancelSellDeposit (2, {from: seller}),
                                 "does not exist");

    await truffleAssert.reverts (dem.cancelBuyOrder (1, {from: buyer}),
                                 "does not exist");
    await truffleAssert.reverts (dem.cancelBuyOrder (3, {from: buyer}),
                                 "does not exist");

    await dem.cancelSellOrder (1, {from: seller});
    await dem.cancelPool (2, {from: pool});
    await dem.cancelSellDeposit (3, {from: seller});
    await dem.cancelBuyOrder (2, {from: buyer});

    await utils.assertNoVault (vm, 1);
    await utils.assertNoVault (vm, 2);
    await utils.assertNoVault (vm, 3);
    await assertNoBuyOrder (2);
  });

  /* ************************************************************************ */

});
