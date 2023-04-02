// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./LimitSelling.sol";
import "./VaultManager.sol";

/**
 * @dev This contract adds support for limit buy orders, together with the
 * liquidity pools needed for it, to Democrit.
 */
contract LimitBuying is LimitSelling
{

  constructor (VaultManager v)
    LimitSelling(v)
  {}

}
