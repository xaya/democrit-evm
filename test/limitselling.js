// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const LimitSellingTestHelper = artifacts.require ("LimitSellingTestHelper");
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

  let wchi, acc, del, ls;
  beforeEach (async () => {
    ({wchi, acc, del} = await utils.xayaEnvironment (supply));
    ls = await LimitSellingTestHelper.new (del.address, tc.address, 101);
    await utils.setupWchi (acc, supply, supply);
    await utils.initialiseContract (ls, supply, "ctrl");
    await wchi.transfer (ls.address, 1000000, {from: supply});

    /* We set up the buyer with a fixed initial balance of WCHI and the seller
       without any, but configured with a founder name "seller".  */
    await utils.setupWchi (acc, supply, buyer);
    await utils.setupWchi (acc, supply, seller);
    await utils.createFounder (ls, seller, "seller");
    await wchi.transfer (supply, await wchi.balanceOf (seller), {from: seller});
    await wchi.transfer (buyer, BALANCE - (await wchi.balanceOf (buyer)),
                         {from: supply});
    assert.equal (await wchi.balanceOf (seller), 0);
    assert.equal (await wchi.balanceOf (buyer), BALANCE);
    await wchi.approve (ls.address, utils.maxUint256, {from: buyer});
  });

  /**
   * Expects that a sell order with the given specifics exists.
   */
  async function assertSellOrder (orderId, vaultId, seller, asset, amount, sats)
  {
    const data = await ls.getSellOrder (orderId);
    assert.equal (data["orderId"], orderId);
    assert.equal (data["vaultId"], vaultId);
    assert.equal (data["owner"], seller);
    assert.equal (data["asset"], asset);
    assert.equal (data["remainingAmount"], amount);
    assert.equal (data["totalSats"], sats);
  }

  /**
   * Expects that no sell order with the given ID exists.
   */
  async function assertNoSellOrder (orderId)
  {
    const data = await ls.getSellOrder (orderId);
    assert.equal (data["orderId"], "0");
    assert.equal (data["vaultId"], "0");
    assert.equal (data["owner"], "");
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
    const orderId = (await ls.nextOrderId ()).toNumber ();
    await ls.createSellOrder (seller, asset, amount, sats, {from});
    const cpHash = (await web3.eth.getBlock ("latest"))["hash"];
    await ls.maybeCreateCheckpoint ();
    return {orderId, cpHash};
  }

  it ("computes the purchase sats correctly", async () => {
    await truffleAssert.reverts (ls.getSatsForPurchase (0, 10, 1),
                                 "non-zero remaining amount");
    await truffleAssert.reverts (ls.getSatsForPurchase (10, 10, 0),
                                 "amount bought must be non-zero");
    await truffleAssert.reverts (ls.getSatsForPurchase (10, 10, 11),
                                 "amount exceeds remaining");
    await truffleAssert.reverts (
        ls.getSatsForPurchase (2, utils.maxUint256, 1),
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
      assert.equal (await ls.getSatsForPurchase (t.amount, t.sats, t.bought),
                    t.expected);
  });

  it ("returns nothing for a non-existing order", async () => {
    assertNoSellOrder (123);
  });

  it ("verifies asset and amount when creating an order", async () => {
    await truffleAssert.reverts (
        ls.createSellOrder ("seller", "gold", 0, 0, {from: seller}),
        "non-zero amount required");
    await truffleAssert.reverts (
        ls.createSellOrder ("seller", "invalid", 1, 1, {from: seller}),
        "invalid asset");
  });

  it ("verifies the sender address's permission", async () => {
    await truffleAssert.reverts (
        ls.createSellOrder ("seller", "gold", 1, 1, {from: buyer}),
        "no permission");
  });

  it ("creates sell orders correctly", async () => {
    await ls.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await ls.createSellOrder ("seller", "silver", 100, 1, {from: seller});

    await utils.assertVault (ls, 1, "seller", "gold", 5);
    await utils.assertVault (ls, 2, "seller", "silver", 100);

    await assertSellOrder (101, 1, "seller", "gold", 5, 10);
    await assertSellOrder (102, 2, "seller", "silver", 100, 1);
  });

  it ("fails to cancel non-existing orders", async () => {
    await ls.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await truffleAssert.reverts (ls.cancelSellOrder (102, {from: seller}),
                                 "does not exist");
  });

  it ("verifies permission when cancelling an order", async () => {
    await ls.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await truffleAssert.reverts (ls.cancelSellOrder (101, {from: buyer}),
                                 "no permission");
  });

  it ("cancels a sell order correctly", async () => {
    await ls.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await ls.createSellOrder ("seller", "silver", 100, 1, {from: seller});

    const afterCreate = await web3.eth.getBlockNumber () + 1;
    await ls.cancelSellOrder (101, {from: seller});
    assert.deepEqual (
      utils.ignoreCheckpoints (await utils.getMoves (acc, afterCreate)), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to seller"
      }}}],
    ]);

    await assertNoSellOrder (101);
    await utils.assertNoVault (ls, 1);

    await assertSellOrder (102, 2, "seller", "silver", 100, 1);
    await utils.assertVault (ls, 2, "seller", "silver", 100);
  });

  it ("fails to accept a non-existing order", async () => {
    const notCheckpointed = (await web3.eth.getBlock ("latest"))["hash"];
    await truffleAssert.reverts (
      ls.acceptSellOrder ({
        orderId: 123, amountBought: 1, buyer: "buyer",
        checkpoint: notCheckpointed,
      }, {from: buyer}),
      "does not exist");
  });

  it ("verifies the checkpoint when accepting an order", async () => {
    await ls.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    const notCheckpointed = (await web3.eth.getBlock ("latest"))["hash"];
    await truffleAssert.reverts (
      ls.acceptSellOrder ({
        orderId: 101, amountBought: 1, buyer: "buyer",
        checkpoint: notCheckpointed,
      }, {from: buyer}),
      "checkpoint is invalid");
  });

  it ("fails for invalid amount bought", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    await truffleAssert.reverts (
      ls.acceptSellOrder ({
        orderId, amountBought: 0, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "amount bought must be non-zero");
    await truffleAssert.reverts (
      ls.acceptSellOrder ({
        orderId, amountBought: 6, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "amount exceeds remaining");
  });

  it ("fails if WCHI balance is not sufficient to buy", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, BALANCE + 1,
                                         seller);
    await truffleAssert.reverts (
      ls.acceptSellOrder ({
        orderId, amountBought: 5, buyer: "buyer", checkpoint: cpHash,
      }, {from: buyer}),
      "WCHI: insufficient balance");
  });

  it ("accepts a full sell order correctly", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    await ls.acceptSellOrder ({
      orderId, amountBought: 5, buyer: "buyer", checkpoint: cpHash,
    }, {from: buyer});

    assert.deepEqual (
      await utils.getMoves (acc, afterCreate), [
      ["ctrl", {"g": {"gid": {
        "send": "5 gold from ctrl:1 to buyer"
      }}}],
    ]);

    await assertNoSellOrder (101);
    await utils.assertNoVault (ls, 1);

    assert.equal (await wchi.balanceOf (seller), 10);
    assert.equal (await wchi.balanceOf (buyer), BALANCE - 10);
  });

  it ("accepts a partial sell order correctly", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    await ls.acceptSellOrder ({
      orderId, amountBought: 2, buyer: "buyer", checkpoint: cpHash,
    }, {from: buyer});

    assert.deepEqual (
      await utils.getMoves (acc, afterCreate), [
      ["ctrl", {"g": {"gid": {
        "send": "2 gold from ctrl:1 to buyer"
      }}}],
    ]);

    await assertSellOrder (101, 1, "seller", "gold", 3, 6);
    await utils.assertVault (ls, 1, "seller", "gold", 3);

    assert.equal (await wchi.balanceOf (seller), 4);
    assert.equal (await wchi.balanceOf (buyer), BALANCE - 4);
  });

  it ("can accept a batch of orders", async () => {
    const {orderId, cpHash}
        = await createCheckpointedOrder ("seller", "gold", 5, 10, seller);
    const afterCreate = await web3.eth.getBlockNumber () + 1;

    await ls.acceptSellOrders ([
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
    await utils.assertNoVault (ls, 1);

    assert.equal (await wchi.balanceOf (seller), 10);
    assert.equal (await wchi.balanceOf (buyer), BALANCE - 10);
  });

});
