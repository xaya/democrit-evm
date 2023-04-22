// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const TestConfig = artifacts.require ("TestConfig");

/** The initial balance held by the seller in WCHI sats.  */
const BALANCE = 1000000;

contract ("Democrit", accounts => {
  let supply = accounts[0];
  let buyer = accounts[1];
  let seller = accounts[2];

  let tc;
  before (async () => {
    tc = await TestConfig.new ();
  });

  let wchi, acc, del, vm, dem;
  beforeEach (async () => {
    ({wchi, acc, del, vm, dem}
        = await utils.setupTradingTest (tc, supply, buyer, seller, BALANCE));
  });

  it ("checks sell orders correctly", async () => {
    await utils.createFounder (vm, buyer, "buyer");
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

});
