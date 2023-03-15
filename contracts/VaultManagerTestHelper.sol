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

}
