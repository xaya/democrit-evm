// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./JsonUtils.sol";

/**
 * @dev Helper contract to expose the JsonUtils library functions to tests.
 */
contract JsonUtilsTestHelper
{

  function escapeString (string memory input)
      public pure returns (string memory)
  {
    return JsonUtils.escapeString (input);
  }

  function escapeBytes (bytes memory input)
      public pure returns (string memory)
  {
    return JsonUtils.escapeString (string (input));
  }

}
