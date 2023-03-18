// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./VaultManager.sol";

/**
 * @dev This is a helper subcontract of VaultManager, exposing the
 * internal methods directly to unit tests.
 */
contract VaultManagerTestHelper is VaultManager
{

  constructor (XayaDelegation del, IDemocritConfig cfg)
    VaultManager(del, cfg)
  {}

  function create (string memory founder, string memory asset,
                   uint initialBalance)
      public returns (uint)
  {
    return createVault (founder, asset, initialBalance);
  }

  function send (uint vaultId, string memory recipient, uint amount)
      public
  {
    sendFromVault (vaultId, recipient, amount);
  }

  /**
   * @dev Creates multiple vaults in the same transaction.  With this we can
   * test a situation where two creates are in the same block.
   */
  function createMany (string memory founder, string memory asset,
                       uint[] calldata ib)
      public
  {
    for (uint i = 0; i < ib.length; ++i)
      createVault (founder, asset, ib[i]);
  }

  /**
   * @dev Executes a vault creation and send in the same transaction.  This is
   * used to test checkpointing in the case that those two appear within a
   * single block.
   */
  function createAndSend (string memory founder, string memory asset,
                          uint initialBalance,
                          string memory recipient, uint amount)
      public
  {
    uint vaultId = createVault (founder, asset, initialBalance);
    sendFromVault (vaultId, recipient, amount);
  }

}
