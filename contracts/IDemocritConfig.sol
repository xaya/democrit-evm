// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

/**
 * @dev This interface defines the methods, that concrete applications
 * need to provide to configure Democrit.  It defines what assets
 * are tradable and how the move formats for creating, funding and
 * sending from vaults are.
 *
 * Vaults need to be implemented in the GSP with behaviour as described
 * in the design doc:
 *
 * https://docs.google.com/document/d/16B-vPKtpjbiCl6XCQaO2-7p8xN-2o5JveYJDHVCIxAw/edit?usp=sharing
 */
interface IDemocritConfig
{

  /**
   * @dev Returns the game ID of the application this is for.
   * The game ID is automatically added to all moves generated
   * by the other functions.
   */
  function gameId () external view returns (string memory);

  /**
   * @dev Checks if the given asset is tradable.
   */
  function isTradableAsset (string memory asset) external view returns (bool);

  /**
   * @dev Returns the move for creating a vault with the given data.
   * The move should be returned as formatted JSON string, and will be
   * wrapped into {"g":{"game id": ... }} by the caller.
   */
  function createVaultMove (string memory controller, uint vaultId,
                            string memory founder,
                            string memory asset, uint amount)
      external view returns (string memory);

  /**
   * @dev Returns the move for sending assets from a vault.  The move returned
   * must be a formatted JSON string, and will be wrapped into
   * {"g":{"game id": ... }} by the caller.
   */
  function sendFromVaultMove (string memory controller, uint vaultId,
                              string memory recipient,
                              string memory asset, uint amount)
      external view returns (string memory);

  /**
   * @dev Returns the move for requesting a checkpoint.  The returned move
   * should be a JSON string.  The caller will wrap it into
   * {"g":{"game id": ... }}.
   */
  function checkpointMove (string memory controller, uint num, bytes32 hash)
      external view returns (string memory);

  /**
   * @dev Returns the move for funding a vault, which is sent from the
   * founding user (not the controller) after a vault has been created.
   * This is sent through the delegation contract, so it should return
   * both the actual move and a hierarchical path for it.  The path
   * will be extended by ["g", "game id", ...] by the caller.
   */
  function fundVaultMove (string memory controller, uint vaultId,
                          string memory founder,
                          string memory asset, uint amount)
      external view returns (string[] memory, string memory);

}
