// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./IDemocritConfig.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @dev An implementation of IDemocritConfig, which is used for testing.
 * It is not tied to any real application or GSP.
 */
contract TestConfig is IDemocritConfig
{

  string public constant gameId = "gid";

  /* For the test, we set up fees as simple percent.  */
  uint64 public constant feeDenominator = 100;
  uint64 public constant maxRelPoolFee = 10;

  /* We support three test assets, gold, silver and copper.  These
     are the pre-computed hashes of those strings.  */
  bytes32 private constant HASH_GOLD = keccak256 ("gold");
  bytes32 private constant HASH_SILVER = keccak256 ("silver");
  bytes32 private constant HASH_COPPER = keccak256 ("copper");

  function isTradableAsset (string memory asset)
      public pure returns (bool)
  {
    bytes32 hash = keccak256 (abi.encodePacked (asset));
    return hash == HASH_GOLD || hash == HASH_SILVER || hash == HASH_COPPER;
  }

  function createVaultMove (string memory controller, uint vaultId,
                            string memory founder,
                            string memory asset, uint amount)
      public pure returns (string memory)
  {
    return string (abi.encodePacked (
        "{\"create\": \"", controller, ":", Strings.toString (vaultId),
        " for ", Strings.toString (amount), " ", asset,
        " of ", founder, "\"}"
    ));
  }

  function checkpointMove (string memory controller, uint num, bytes32 hash)
      public pure returns (string memory)
  {
    return string (abi.encodePacked (
        "{\"checkpoint\": \"", Strings.toString (num), " ",
        Strings.toHexString (uint256 (hash)),
        " from ", controller, "\"}"
    ));
  }

  function sendFromVaultMove (string memory controller, uint vaultId,
                              string memory recipient,
                              string memory asset, uint amount)
      public pure returns (string memory)
  {
    return string (abi.encodePacked (
        "{\"send\": \"", Strings.toString (amount), " ", asset,
        " from ", controller, ":", Strings.toString (vaultId),
        " to ", recipient, "\"}"
    ));
  }

  function fundVaultMove (string memory controller, uint vaultId,
                            string memory founder,
                            string memory asset, uint amount)
      public pure returns (string[] memory path, string memory mv)
  {
    mv = string (abi.encodePacked (
        "{\"", controller, ":", Strings.toString (vaultId), "\": ",
        "\"with ", Strings.toString (amount), " ", asset,
        " by ", founder, "\"}"
    ));

    path = new string[] (1);
    path[0] = "fund";
  }

}
