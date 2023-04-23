// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const TestConfig = artifacts.require ("TestConfig");

/** The initial balance held by the seller in WCHI sats.  */
const BALANCE = 1000000;

contract ("Democrit", accounts => {
  const supply = accounts[0];
  const buyer = accounts[1];
  const seller = accounts[2];
  const pool = accounts[3];
  const poolSigner = accounts[4];

  let tc;
  before (async () => {
    tc = await TestConfig.new ();
  });

  let wchi, acc, del, vm, dem;
  beforeEach (async () => {
    ({wchi, acc, del, vm, dem}
        = await utils.setupTradingTest (tc, supply, buyer, seller, BALANCE));
    await utils.setupPoolOperator (dem, supply, pool, "pool", poolSigner);
  });

  it ("checks sell orders correctly", async () => {
    const tokenId = await acc.tokenIdForName ("p", "buyer");

    await dem.createSellOrder ("seller", "gold", 5, 10, {from: seller});
    await dem.createSellOrder ("buyer", "silver", 100, 1, {from: buyer});
    await acc.safeTransferFrom (buyer, seller, tokenId, {from: buyer});

    const data = await dem.checkSellOrders ([101, 102, 103]);
    assert.equal (data.length, 3);

    assert.equal (data[0].exists, true);
    assert.equal (data[0].valid, true);
    utils.assertSellOrderData (data[0].order, 101, 1, seller, "seller",
                               "gold", 5, 10);

    assert.equal (data[1].exists, true);
    assert.equal (data[1].valid, false);
    utils.assertSellOrderData (data[1].order, 102, 2, buyer, "buyer",
                               "silver", 100, 1);

    assert.equal (data[2].exists, false);
    assert.equal (data[2].valid, false);
    utils.assertSellOrderNull (data[2].order);
  });

  it ("computes the total buy cost correctly", async () => {
    const tests = [
      {amount: 100, sats: 0, relFee: 0, bought: 0, cost: 0},
      {amount: 100, sats: 0, relFee: 0, bought: 100, cost: 0},
      {amount: 100, sats: 1000, relFee: 0, bought: 20, cost: 200},
      {amount: 100, sats: 1000, relFee: 10, bought: 20, cost: 220},
      {amount: 100, sats: 1001, relFee: 1, bought: 50, cost: 501 + 6},
      {amount: 100, sats: 1001, relFee: 100, bought: 50, cost: 501 * 2},
    ];

    for (const t of tests)
      assert.equal (
          await dem.getTotalBuyCost (t["amount"], t["sats"], t["relFee"],
                                     t["bought"]),
          t["cost"]);
  });

  it ("computes the max buy correctly", async () => {
    /**
     * Tests the getMaxBuy function with the given inputs.  This verifies that
     * the output is the largest value for which the total cost does not
     * exceed the available amount (unless it is the full available amount
     * already).
     */
    async function testMaxBuy (remaining, sats, relFee, available)
    {
      const maxBuy = await dem.getMaxBuy (remaining, sats, relFee, available);
      assert.isAtMost (maxBuy.toNumber (), remaining);
      if (maxBuy.toNumber () == remaining)
        return;

      const cost1 = await dem.getTotalBuyCost (remaining, sats, relFee, maxBuy);
      assert.isAtMost (cost1.toNumber (), available);
      const cost2 = await dem.getTotalBuyCost (remaining, sats, relFee,
                                               maxBuy.toNumber () + 1);
      assert.isAbove (cost2.toNumber (), available);
    }

    await testMaxBuy (100, 0, 0, 10);
    await testMaxBuy (100, 1000, 0, 20);
    await testMaxBuy (100, 1000, 10, 20);
    await testMaxBuy (100, 1000, 10, 1000000);
    await testMaxBuy (100, 1001, 1, 20);
    await testMaxBuy (100, 1001, 100, 20);
    await testMaxBuy (1000027, 10, 1, 9);
    await testMaxBuy (103, 1007, 2, 1020);

    /* Do some poor man's fuzz testing.  */
    for (let fee = 0; fee <= 120; fee += 11)
      for (let available = 0; available <= 1100; available += 173)
        {
          await testMaxBuy (103, 1007, fee, available);
          await testMaxBuy (1042999, 1007, fee, available);
        }
  });

  it ("does basic buy-order checks", async () => {
    const tokenId = await acc.tokenIdForName ("p", "seller");

    await utils.setupWchi (acc, supply, seller);
    await wchi.approve (dem.address, utils.maxUint256, {from: seller});

    await dem.createPool ("pool", "", "gold", 100, 10, {from: pool});
    await dem.createPool ("pool", "", "gold", 100, 10, {from: pool});
    const cpHash = await utils.createCheckpoint (vm);

    await dem.createBuyOrder ("buyer", "gold", 10, 100, 1, cpHash,
                              {from: buyer});
    await dem.createBuyOrder ("buyer", "gold", 10, 200, 2, cpHash,
                              {from: buyer});
    await dem.createBuyOrder ("seller", "gold", 10, 300, 1, cpHash,
                              {from: seller});

    await dem.cancelPool (2, {from: pool});
    await acc.safeTransferFrom (seller, buyer, tokenId, {from: seller});

    const data = await dem.checkBuyOrders ([101, 102, 103, 104]);
    assert.equal (data.length, 4);

    assert.equal (data[0].exists, true);
    assert.equal (data[0].valid, true);
    utils.assertBuyOrderData (data[0].order, 101, 1, "pool", 100, 10,
                              buyer, "buyer", "gold", 10, 100);

    assert.equal (data[1].exists, false);
    assert.equal (data[1].valid, false);
    utils.assertBuyOrderNull (data[1].order);

    assert.equal (data[2].exists, true);
    assert.equal (data[2].valid, false);
    utils.assertBuyOrderData (data[2].order, 103, 1, "pool", 100, 10,
                              seller, "seller", "gold", 10, 300);

    assert.equal (data[3].exists, false);
    assert.equal (data[3].valid, false);
    utils.assertBuyOrderNull (data[3].order);
  });

  it ("returns the available WCHI for buy orders", async () => {
    await dem.createPool ("pool", "", "gold", 100, 10, {from: pool});
    const cpHash = await utils.createCheckpoint (vm);
    await dem.createBuyOrder ("buyer", "gold", 10, 100, 1, cpHash,
                              {from: buyer});

    await utils.setWchiBalance (wchi, buyer, 42, supply);
    let [data] = await dem.checkBuyOrders ([101]);
    assert.equal (data.availableSats, 42);

    await wchi.approve (dem.address, 7, {from: buyer});
    [data] = await dem.checkBuyOrders ([101]);
    assert.equal (data.availableSats, 7);

    await utils.setWchiBalance (wchi, buyer, 0, supply);
    [data] = await dem.checkBuyOrders ([101]);
    assert.equal (data.availableSats, 0);
  });

  it ("returns the max buy with checked orders", async () => {
    await dem.createPool ("pool", "", "gold", 100, 10, {from: pool});
    await dem.createSellDeposit ("seller", "gold", 100, {from: seller});
    const cpHash = await utils.createCheckpoint (vm);
    await dem.createBuyOrder ("buyer", "gold", 90, 90, 1, cpHash,
                              {from: buyer});
    await dem.createBuyOrder ("buyer", "gold", 100, 0, 1, cpHash,
                              {from: buyer});

    /* Both orders can be taken in full, the limit is the available
       amount in the order.  */
    await utils.setWchiBalance (wchi, buyer, 1000, supply);
    let [data1, data2] = await dem.checkBuyOrders ([101, 102]);
    assert.equal (data1.maxBuy, 90);
    assert.equal (data2.maxBuy, 100);

    /* By taking part of the first order, we reduce the pool's available
       balance accordingly.  Then the second order's max buy will be determined
       by what is available in the pool.  */
    const {vault: deposit, signature}
        = await utils.signVaultCheck (dem, "pool", poolSigner, 2, cpHash);
    await dem.acceptBuyOrder ({
        orderId: 101, amountSold: 50,
        deposit, signature,
    }, {from: seller});
    [data1, data2] = await dem.checkBuyOrders ([101, 102]);
    assert.equal (data1.maxBuy, 40);
    assert.equal (data2.maxBuy, 50);

    /* We reduce the WCHI balance of the buyer, this limits the maximum amount
       that can be bought.  */
    await utils.setWchiBalance (wchi, buyer, 22, supply);
    [data1, data2] = await dem.checkBuyOrders ([101, 102]);
    assert.equal (data1.maxBuy, 20);
    assert.equal (data2.maxBuy, 50);

    /* Even at 0 WCHI, the order at price zero can be bought.  */
    await utils.setWchiBalance (wchi, buyer, 0, supply);
    [data1, data2] = await dem.checkBuyOrders ([101, 102]);
    assert.equal (data1.maxBuy, 0);
    assert.equal (data2.maxBuy, 50);
  });

});
