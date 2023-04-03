// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./Democrit.sol";

/**
 * @dev Helper subcontract of Democrit, which does some tweaks for testing.
 */
contract DemocritTestHelper is Democrit
{

  constructor (XayaDelegation del, IDemocritConfig cfg, uint firstId)
    Democrit(del, cfg)
  {
    /* In tests, we start with a higher order ID.  This ensures that
       order IDs do not match the associated vault IDs, which could lead
       to bugs undiscovered by tests (e.g. when the two are mixed up).  */
    nextOrderId = firstId;
  }

}
