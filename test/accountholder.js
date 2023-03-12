// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const utils = require ("./testutils");

const AccountHolderTestHelper = artifacts.require ("AccountHolderTestHelper");

contract ("AccountHolder", accounts => {
  let wchiSupply = accounts[0];

  let wchi, acc, del, ah;
  beforeEach (async () => {
    ({wchi, acc, del} = await utils.xayaEnvironment (wchiSupply));
    ah = await AccountHolderTestHelper.new (del.address);

    /* Approve WCHI from the main account, so it can register names.  */
    await wchi.approve (acc.address, utils.maxUint256, {from: wchiSupply});

    /* Transfer some WCHI to the AccountHolder, so it can actually
       pay for moves.  */
    await wchi.transfer (ah.address, 1000000, {from: wchiSupply});
  });

  it ("rejects unexpected NFT transfers", async () => {
    const env2 = await utils.xayaEnvironment (wchiSupply);
    const acc2 = env2.acc;

    const tokenId1 = await acc.tokenIdForName ("g", "x");
    await acc.register ("g", "x", {from: wchiSupply});
    const tokenId2 = await acc2.tokenIdForName ("p", "y");
    await acc2.register ("p", "y", {from: wchiSupply});

    await truffleAssert.reverts (
        acc.safeTransferFrom (wchiSupply, ah.address, tokenId1,
                              {from: wchiSupply}),
        "only Xaya accounts");
    await truffleAssert.reverts (
        acc2.safeTransferFrom (wchiSupply, ah.address, tokenId2,
                               {from: wchiSupply}),
        "only Xaya names");
  });

  it ("can be initialised correctly", async () => {
    const tokenId = await acc.tokenIdForName ("p", "foo");
    await acc.register ("p", "foo", {from: wchiSupply});

    assert.isFalse (await ah.initialised ());
    await acc.safeTransferFrom (wchiSupply, ah.address, tokenId,
                                {from: wchiSupply});

    assert.isTrue (await ah.initialised ());
    assert.equal (await ah.account (), "foo");
  });

  it ("can only be initialised once", async () => {
    const tokenId = await acc.tokenIdForName ("p", "wrong");
    await acc.register ("p", "wrong", {from: wchiSupply});

    await utils.initialiseContract (acc, wchiSupply, "right", ah);

    await truffleAssert.reverts (
        acc.safeTransferFrom (wchiSupply, ah.address, tokenId,
                              {from: wchiSupply}),
        "already initialised");
    assert.equal (await ah.account (), "right");
  });

  it ("can send moves", async () => {
    await truffleAssert.reverts (
        ah.sendMoveFromTest ("move"),
        "is not initialised");
    await utils.initialiseContract (acc, wchiSupply, "foo", ah);

    await ah.sendMoveFromTest ("some");
    await ah.sendMoveFromTest ("moves");

    const moves = await acc.getPastEvents ("Move",
                                           {fromBlock: 0, toBlock: "latest"});
    assert.equal (moves.length, 2);
    assert.equal (moves[0].args.ns, "p");
    assert.equal (moves[0].args.name, "foo");
    assert.equal (moves[0].args.mv, "some");
    assert.equal (moves[1].args.mv, "moves");
  });

});
