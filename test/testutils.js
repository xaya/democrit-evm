// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleContract = require ("@truffle/contract");

const wchiData = require ("@xaya/wchi/build/contracts/WCHI.json");
const WCHI = truffleContract (wchiData);
WCHI.setProvider (web3.currentProvider);

const policyData
    = require ("@xaya/eth-account-registry/build/contracts/TestPolicy.json");
const TestPolicy = truffleContract (policyData);
TestPolicy.setProvider (web3.currentProvider);
const accountsData
    = require ("@xaya/eth-account-registry/build/contracts/XayaAccounts.json");
const XayaAccounts = truffleContract (accountsData);
XayaAccounts.setProvider (web3.currentProvider);

const delegatorData
    = require ("@xaya/eth-delegator-contract/build/contracts/XayaDelegation.json");
const XayaDelegation = truffleContract (delegatorData);
XayaDelegation.setProvider (web3.currentProvider);

const DemocritTestHelper = artifacts.require ("DemocritTestHelper");

const nullAddress = "0x0000000000000000000000000000000000000000";
const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

/* ************************************************************************** */

/**
 * Sets up the basic contract environment including WCHI, XayaAccounts
 * with a test policy, and XayaDelegation.  The provided address is used
 * to construct all of them from, which effectively means that it will
 * hold the initial WCHI supply and also be owner of the contracts
 * where applicable.
 *
 * The method returns the constructed contract instances {wchi, acc, del}.
 */
async function xayaEnvironment (deployer)
{
  wchi = await WCHI.new ({from: deployer});
  const policy = await TestPolicy.new ({from: deployer});
  acc = await XayaAccounts.new (wchi.address, policy.address, {from: deployer});
  del = await XayaDelegation.new (acc.address, nullAddress, {from: deployer});
  return {wchi, acc, del};
}

/**
 * Initialises the contract (which is an AccountHolder or a subcontract)
 * by registering the given name and transferring it to it.
 */
async function initialiseContract (contract, fromAccount, name)
{
  const acc = await XayaAccounts.at (await contract.accountRegistry ());

  const tokenId = await acc.tokenIdForName ("p", name);
  await acc.register ("p", name, {from: fromAccount});
  await acc.safeTransferFrom (fromAccount, contract.address, tokenId,
                              {from: fromAccount});
  assert.isTrue (await contract.initialised ());
}

/**
 * Transfers some WCHI from supply to the given address and approves
 * WCHI on the accounts registry.  This is basically the setup required to
 * register names with the given address.
 */
async function setupWchi (acc, supply, addr)
{
  const wchi = await WCHI.at (await acc.wchiToken ());
  await wchi.transfer (addr, 1000000, {from: supply});
  await wchi.approve (acc.address, maxUint256, {from: addr});
}

/**
 * Registers a name (to be used as founder) with the required approvals set
 * up for the delegation contract.
 */
async function createFounder (vm, fromAccount, name)
{
  const del = await XayaDelegation.at (await vm.delegator ());
  const acc = await XayaAccounts.at (await vm.accountRegistry ());

  await acc.register ("p", name, {from: fromAccount});
  await acc.setApprovalForAll (del.address, true, {from: fromAccount});
  await del.grant ("p", name, ["g"], vm.address, maxUint256, false,
                   {from: fromAccount});
}

/**
 * Sets up the testing environment we use for "full trading" tests.
 * This deploys a DemocritTestHelper instance in addition to the basic
 * Xaya contracts, and sets up a buyer and seller account.  The buyer
 * has a given initial balance of WCHI, and the seller owns a founder
 * name "seller".
 */
async function setupTradingTest (testConfig, supply, buyer, seller, balance)
{
  const {wchi, acc, del} = await xayaEnvironment (supply);
  const dem = await DemocritTestHelper.new (
      del.address, testConfig.address, 101);
  await setupWchi (acc, supply, supply);
  await initialiseContract (dem, supply, "ctrl");
  await wchi.transfer (dem.address, 1000000, {from: supply});

  /* We set up the buyer with a fixed initial balance of WCHI and the seller
     without any, but configured with a founder name "seller".  */
  await setupWchi (acc, supply, buyer);
  await setupWchi (acc, supply, seller);
  await createFounder (dem, seller, "seller");
  await wchi.transfer (supply, await wchi.balanceOf (seller), {from: seller});
  await wchi.transfer (buyer, balance - (await wchi.balanceOf (buyer)),
                       {from: supply});
  assert.equal (await wchi.balanceOf (seller), 0);
  assert.equal (await wchi.balanceOf (buyer), balance);
  await wchi.approve (dem.address, maxUint256, {from: buyer});

  return {wchi, acc, del, dem};
}

/* ************************************************************************** */

/**
 * Returns the moves sent on the Xaya accounts registry since the given
 * block height.
 *
 * Each entry returned will be an array of two elements, the name as string and
 * the move as JSON.  Only events with namespace "p" will be returned.
 */
async function getMoves (acc, fromBlock)
{
  const moves = await acc.getPastEvents ("Move",
                                         {fromBlock, toBlock: "latest"});
  return moves
      .filter (m => (m.args.ns == "p"))
      .map (m => [m.args.name, JSON.parse (m.args.mv)]);
}

/**
 * Returns the current best block hash.
 */
async function getBestBlock ()
{
  return (await web3.eth.getBlock ("latest"))["hash"];
}

/**
 * Filters the array of moves provided (as from getMoves), removing
 * all checkpoint moves.  They get auto-triggered during some otherwise
 * unrelated things, and thus for some tests it helps to filter them out
 * and concentrate on other things.
 */
function ignoreCheckpoints (moves)
{
  return moves.filter (m => !("checkpoint" in m[1]["g"]["gid"]));
}

/**
 * Creates a checkpoint in the contract and returns its hash.
 */
async function createCheckpoint (vm)
{
  const cpHash = await getBestBlock ();
  await vm.maybeCreateCheckpoint ();
  return cpHash;
}

/* ************************************************************************** */

/**
 * Asserts that the data for the vault with the given ID matches
 * the expected one.
 */
async function assertVault (vm, id, founder, asset, balance)
{
  const data = await vm.getVault (id);
  assert.equal (data["founder"], founder);
  assert.equal (data["asset"], asset);
  assert.equal (data["balance"], balance.toString ());
}

/**
 * Asserts that the given vault does not exist or has been emptied.
 */
async function assertNoVault (vm, id)
{
  const data = await vm.getVault (id);
  assert.equal (data["founder"], "");
  assert.equal (data["asset"], "");
  assert.equal (data["balance"], "0");
}

/**
 * Asserts that the given data value matches an existing sell order
 * with the passed fields.
 */
function assertSellOrderData (data, orderId, vaultId, creator, seller,
                              asset, amount, sats)
{
  assert.equal (data["orderId"], orderId);
  assert.equal (data["vaultId"], vaultId);
  assert.equal (data["creator"], creator);
  assert.equal (data["seller"], seller);
  assert.equal (data["asset"], asset);
  assert.equal (data["remainingAmount"], amount);
  assert.equal (data["totalSats"], sats);
}

/**
 * Asserts that the given data value matches the null data for a
 * sell order (that doesn't exist).
 */
function assertSellOrderNull (data)
{
  assert.equal (data["orderId"], "0");
  assert.equal (data["vaultId"], "0");
  assert.equal (data["creator"], nullAddress);
  assert.equal (data["seller"], "");
  assert.equal (data["asset"], "");
  assert.equal (data["remainingAmount"], "0");
  assert.equal (data["totalSats"], "0");
}

/* ************************************************************************** */

module.exports = {
  nullAddress,
  maxUint256,
  xayaEnvironment,
  initialiseContract,
  setupWchi,
  createFounder,
  setupTradingTest,
  getMoves,
  getBestBlock,
  ignoreCheckpoints,
  createCheckpoint,
  assertVault,
  assertNoVault,
  assertSellOrderData,
  assertSellOrderNull,
};
