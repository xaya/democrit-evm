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

const nullAddress = "0x0000000000000000000000000000000000000000";
const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

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

module.exports = {
  nullAddress,
  maxUint256,
  xayaEnvironment,
  initialiseContract,
  getMoves,
};
