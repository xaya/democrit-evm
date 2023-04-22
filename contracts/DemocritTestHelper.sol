// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./Democrit.sol";
import "./VaultManager.sol";

/**
 * @dev Helper subcontract of Democrit, which does some tweaks for testing.
 */
contract DemocritTestHelper is Democrit
{

  constructor (VaultManager v, uint firstId)
    Democrit(v)
  {
    /* In tests, we start with a higher order ID.  This ensures that
       order IDs do not match the associated vault IDs, which could lead
       to bugs undiscovered by tests (e.g. when the two are mixed up).  */
    nextOrderId = firstId;
  }

}
