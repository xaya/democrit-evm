// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const TestConfig = artifacts.require ("TestConfig");

/** The initial balance held by the seller in WCHI sats.  */
const BALANCE = 1000000;

contract ("LimitSelling", accounts => {
  let supply = accounts[0];
  let buyer = accounts[1];
  let seller = accounts[2];

  let tc;
  before (async () => {
    tc = await TestConfig.new ();
  });

  let wchi, acc, del, dem;
  beforeEach (async () => {
    ({wchi, acc, del, dem}
        = await utils.setupTradingTest (tc, supply, buyer, seller, BALANCE));
  });

  /**
   * Expects that a sell order with the given specifics exists.
   */
  async function assertSellOrder (orderId, vaultId, creator, seller,
                                  asset, amount, sats)
  {
    const data = await dem.getSellOrder (orderId);
    assert.equal (data["orderId"], orderId);
    assert.equal (data["vaultId"], vaultId);
    assert.equal (data["creator"], creator);
    assert.equal (data["seller"], seller);
    assert.equal (data["asset"], asset);
    assert.equal (data["remainingAmount"], amount);
    assert.equal (data["totalSats"], sats);
  }

  /**
   * Expects that no sell order with the given ID exists.
   */
  async function assertNoSellOrder (orderId)
  {
    const data = await dem.getSellOrder (orderId);
    assert.equal (data["orderId"], "0");
    assert.equal (data["vaultId"], "0");
    assert.equal (data["creator"], utils.nullAddress);
    assert.equal (data["seller"], "");
    assert.equal (data["asset"], "");
    assert.equal (data["remainingAmount"], "0");
    assert.equal (data["totalSats"], "0");
  }

  /**
   * Creates a new sell order and checkpoints the associated vault
   * afterwards.  Returns {orderId, checkpoint}.
   */
  async function createCheckpointedOrder (seller, asset, amount, sats, from)
  {
    const orderId = (await dem.nextOrderId ()).toNumber ();
    await dem.createSellOrder (seller, asset, amount, sats, {from});
    const cpHash = (await web3.eth.getBlock ("latest"))["hash"];
    await dem.maybeCreateCheckpoint ();
    return {orderId, cpHash};
  }

  it ("computes the purchase sats correctly", async () => {
    await truffleAssert.reverts (dem.getSatsForPurchase (0, 10, 1),
                                 "non-zero remaining amount");
    await truffleAssert.reverts (dem.getSatsForPurchase (10, 10, 0),
                                 "amount bought must be non-zero");
    await truffleAssert.reverts (dem.getSatsForPurchase (10, 10, 11),
                                 "amount exceeds remaining");
    await truffleAssert.reverts (
        dem.getSatsForPurchase (2, utils.maxUint256, 1),
        "revert");

    const tests = [
      /* Some examples with full purchase.  */
      {amount: 100, sats: 42, bought: 100, expected: 42},
      {amount: 100, sats: 0, bought: 100, expected: 0},
      {amount: 1, sats: 1, bought: 1, expected: 1},
      /* These two would overflow, but work due to the full purchase
         short-circuit condition.  */
      {
        amount: 2,
        sats: utils.maxUint256,
        bought: 2,
        expected: utils.maxUint256,
      },
      {
        amount: utils.maxUint256,
        sats: 2,
        bought: utils.maxUint256,
        expected: 2,
      },

      /* Zero purchase price is ok.  */
      {amount: 100, sats: 0, bought: 20, expected: 0},
      {amount: utils.maxUint256, sats: 0, bought: 100, expected: 0},

      /* Rounding up to the next sat.  */
      {amount: 100, sats: 1, bought: 1, expected: 1},
      {amount: 100, sats: 1, bought: 99, expected: 1},

      /* Proportional amount.  */
      {amount: 100, sats: 1000, bought: 42, expected: 420},
      {amount: 100, sats: 5, bought: 33, expected: 2},
    ];
    for (const t of tests)
      assert.equal (await dem.getSatsForPurchase (t.amount, t.sats, t.bought),
                    t.expected);
  });

  it ("returns nothing for a non-existing order", async () => {
    assertNoSellOrder (123);
  });

  it ("verifies asset and amount when creating an order", async () => {
    await truffleAssert.reverts (
        dem.createSellOrder ("seller", "gold", 0, 0, {from: seller}),
        "non-zero amount required");
    await truffleAssert.reverts (
        dem.createSellOrder ("seller", "invalid", 1, 1, {from: seller}),
        "invalid asset");
  });

  it ("verifies the sender address's permission", async () => {
    await truffleAssert.reverts (
        dem.createSellOrder ("seller", "gold", 1, 1, {from: buyer}),
        "no permission");
  });

  it ("creates sell orders correctly", async () => {
    await dem.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await dem.createSellOrder ("seller", "silver", 100, 1, {from: seller});

    await utils.assertVault (dem, 1, "seller", "gold", 5);
    await utils.assertVault (dem, 2, "seller", "silver", 100);

    await assertSellOrder (101, 1, seller, "seller", "gold", 5, 10);
    await assertSellOrder (102, 2, seller, "seller", "silver", 100, 1);
  });

  it ("fails to cancel non-existing orders", async () => {
    await dem.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await truffleAssert.reverts (dem.cancelSellOrder (102, {from: seller}),
                                 "does not exist");
  });

  it ("verifies permission when cancelling an order", async () => {
    await dem.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await truffleAssert.reverts (dem.cancelSellOrder (101, {from: buyer}),
                                 "no permission");
  });

  it ("cancels a sell order correctly", async () => {
    await dem.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await dem.createSellOrder ("seller", "silver", 100, 1, {from: seller});

    const afterCreate = await web3.eth.getBlockNumber () + 1;
    await dem.cancelSellOrder (101, {from: seller});
    assert.deepEqual (
      utils.ignoreCheckpoints (await utils.getMoves (acc, afterCreate)), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to seller"
      }}}],
    ]);

    await assertNoSellOrder (101);
    await utils.assertNoVault (dem, 1);

    await assertSellOrder (102, 2, seller, "seller", "silver", 100, 1);
    await utils.assertVault (dem, 2, "seller", "silver", 100);
  });

  it ("fails to accept a non-existing order", async () => {
    const notCheckpointed = (await web3.eth.getBlock ("latest"))["hash"];
    await truffleAssert.reverts (
      dem.acceptSellOrder ({
        orderId: 123, amountBought: 1, buyer: "buyer",
        checkpoint: notCheckpointed,
      }, {from: buyer}),
      "does not exist");
  });

  it ("verifies the checkpoint when accepting an order", async () => {
    await dem.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    const notCheckpointed = (await web3.eth.getBlock ("latest"))["hash"];
    await truffleAssert.reverts (
      dem.acceptSellOrder ({
        orderId: 101, amountBought: 1, buyer: "buyer",
        checkpoint: notCheckpointed,
      }, {from: buyer}),
      "checkpoint is invalid");
  });

  it ("fails for invalid amount bought", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    await truffleAssert.reverts (
      dem.acceptSellOrder ({
        orderId, amountBought: 0, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "amount bought must be non-zero");
    await truffleAssert.reverts (
      dem.acceptSellOrder ({
        orderId, amountBought: 6, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "amount exceeds remaining");
  });

  it ("fails if WCHI balance is not sufficient to buy", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, BALANCE + 1,
                                         seller);
    await truffleAssert.reverts (
      dem.acceptSellOrder ({
        orderId, amountBought: 5, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "WCHI: insufficient balance");
  });

  it ("fails if the seller name has been transferred", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    const tokenId = await acc.tokenIdForName ("p", "seller");
    await acc.safeTransferFrom (seller, buyer, tokenId, {from: seller});

    await truffleAssert.reverts (
      dem.acceptSellOrder ({
        orderId, amountBought: 5, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "seller name has been transferred");

    /* Cancelling the order is still possible, so the new owner can get
       back the locked funds.  */
    await dem.cancelSellOrder (orderId, {from: buyer});
    assert.deepEqual (
      await utils.getMoves (acc, afterCreate), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to seller"
      }}}],
    ]);
    assertNoSellOrder (orderId);
    utils.assertNoVault (dem, 1);
  });

  it ("accepts a full sell order correctly", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    await dem.acceptSellOrder ({
      orderId, amountBought: 5, buyer: "buyer", checkpoint: cpHash,
    }, {from: buyer});

    assert.deepEqual (
      await utils.getMoves (acc, afterCreate), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to buyer"
      }}}],
    ]);

    await assertNoSellOrder (101);
    await utils.assertNoVault (dem, 1);

    assert.equal (await wchi.balanceOf (seller), 10);
    assert.equal (await wchi.balanceOf (buyer), BALANCE - 10);
  });

  it ("accepts a partial sell order correctly", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    await dem.acceptSellOrder ({
      orderId, amountBought: 2, buyer: "buyer", checkpoint: cpHash,
    }, {from: buyer});

    assert.deepEqual (
      await utils.getMoves (acc, afterCreate), [
      ["ctrl", {"g": {"gid": {
        "send": "2 gold from ctrl:1 to buyer"
      }}}],
    ]);

    await assertSellOrder (101, 1, seller, "seller", "gold", 3, 6);
    await utils.assertVault (dem, 1, "seller", "gold", 3);

    assert.equal (await wchi.balanceOf (seller), 4);
    assert.equal (await wchi.balanceOf (buyer), BALANCE - 4);
  });

  it ("can accept a batch of orders", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    await dem.acceptSellOrders ([
      {orderId, amountBought: 2, buyer: "buyer", checkpoint: cpHash},
      {orderId, amountBought: 3, buyer: "buyer", checkpoint: cpHash},
    ], {from: buyer});

    assert.deepEqual (
      await utils.getMoves (acc, afterCreate), [
      ["ctrl", {"g": {"gid": {
        "send": "2 gold from ctrl:1 to buyer"
      }}}],
      ["ctrl", {"g": {"gid": {
        "send": "3 gold from ctrl:1 to buyer"
      }}}],
    ]);

    await assertNoSellOrder (101);
    await utils.assertNoVault (dem, 1);

    assert.equal (await wchi.balanceOf (seller), 10);
    assert.equal (await wchi.balanceOf (buyer), BALANCE - 10);
  });

});
