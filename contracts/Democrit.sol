// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./LimitSelling.sol";

/**
 * @dev This is the main contract for the Democrit exchange.  Most of the
 * functionality is inherited from parent contracts already and just
 * consolidated here.
 */
contract Democrit is LimitSelling
{

  constructor (XayaDelegation del, IDemocritConfig cfg)
    LimitSelling(del, cfg)
  {}

  /* TODO: When we have limit buy orders, add view methods here that
     the frontend can use to query for the status of buy orders, i.e.
     check that/if the buyer has enough WCHI available and approved,
     the liquidity pools associated have enough funds and so on.  */

}
