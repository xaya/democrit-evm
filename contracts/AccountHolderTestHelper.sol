// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./AccountHolder.sol";

/**
 * @dev Basic subclass of AccountHolder, which exposes sendMove
 * to the unit tests.
 */
contract AccountHolderTestHelper is AccountHolder
{

  constructor (XayaDelegation del)
    AccountHolder(del)
  {}

  function sendMoveFromTest (string memory mv) public
  {
    sendMove (mv);
  }

}
