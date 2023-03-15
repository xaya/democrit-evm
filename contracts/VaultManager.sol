// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./AccountHolder.sol";
import "./IDemocritConfig.sol";
import "./JsonUtils.sol";

/**
 * @dev This is a contract that manages a set of trading vaults in a
 * Democrit application.  It keeps track of each vault's state as it should
 * be inside the GSP, with the only unknown bit being whether or not the
 * vault was created at all (due to not knowing the real GSP state on chain).
 *
 * The contract is an AccountHolder, with the owned account acting as
 * controller for the vaults.  Vaults can be created (and funded in the
 * same transaction), and assets can be sent from vaults to arbitrary users.
 * These functions are exposed as internal methods, which subcontracts can
 * use to explicitly implement certain logic, e.g. trading.
 */
contract VaultManager is AccountHolder
{

  /** @dev The contract defining the Democrit config for this app.  */
  IDemocritConfig public immutable config;

  /**
   * @dev The data stored on chain for the state of each vault controlled
   * by the contract's account.  Only the balance is mutable after creation.
   */
  struct VaultData
  {

    /* The controller of the vault will always be the name owned
       by the AccountHolder, and the ID is known as index into the
       vaults array by which this struct is accessed.  */

    /** @dev The founder / owner account of the asset inside.  */
    string founder;

    /** @dev The asset type inside the vault.  */
    string asset;

    /** @dev The current balance as we know it on chain.  */
    uint balance;

  }

  /** @dev All vaults by ID.  Emptied vaults will be deleted.  */
  VaultData[] private vaults;

  /** @dev Emitted when a new vault is created and funded.  */
  event VaultCreated (string controller, uint id, string founder,
                      string asset, uint initialBalance);

  /** @dev Emitted when funds are sent from a vault.  */
  event SentFromVault (string controller, uint id, string recipient,
                       string asset, uint amount);

  /** @dev Emitted when the balance of a vault changes.  */
  event VaultChanged (string controller, uint id, string asset, uint balance);

  /** @dev Emitted when an empty vault gets removed.  */
  event VaultEmptied (string controller, uint id);

  constructor (XayaDelegation del, IDemocritConfig cfg)
    AccountHolder(del)
  {
    config = cfg;
  }

  /**
   * @dev Returns the number of vaults that have been created (even if some
   * of them might have been emptied in the mean time).  This is also the
   * next ID given to a new vault.
   */
  function getNumVaults () public view returns (uint)
  {
    return vaults.length;
  }

  /**
   * @dev Returns the data for a given vault, or a zero struct if it does
   * not exist or has been emptied.
   */
  function getVault (uint vaultId) public view returns (VaultData memory res)
  {
    if (vaultId < vaults.length)
      res = vaults[vaultId];
  }

  /**
   * @dev Creates and funds a new vault.  It is not known whether or not the
   * founding user has enough of the given asset to fund the vault, so whether
   * or not the creation succeeds.  This is something that external users
   * need to check before relying on the existence of a vault.  However, in case
   * the vault is created successfully (i.e. they can query for it and it
   * exists), it is guaranteed that the contract's state will keep matching
   * the in-game state of the vault.  Returns the vault ID.
   */
  function createVault (string memory founder, string memory asset,
                        uint initialBalance)
      internal returns (uint)
  {
    require (config.isTradableAsset (asset), "invalid asset for vault");
    require (initialBalance > 0, "initial balance must be positive");

    uint vaultId = vaults.length;
    VaultData storage data = vaults.push ();
    data.founder = founder;
    data.asset = asset;
    data.balance = initialBalance;

    string memory createMv
        = config.createVaultMove (account, vaultId, founder,
                                  asset, initialBalance);
    sendGameMove (createMv);

    (string[] memory path, string memory fundMv) =
        config.fundVaultMove (account, vaultId, founder,
                              asset, initialBalance);
    string[] memory fullPath = new string[] (path.length + 2);
    fullPath[0] = "g";
    fullPath[1] = config.gameId ();
    for (uint i = 0; i < path.length; ++i)
      fullPath[i + 2] = path[i];
    delegator.sendHierarchicalMove ("p", founder, fullPath, fundMv);

    emit VaultCreated (account, vaultId, founder, asset, initialBalance);

    return vaultId;
  }

  /**
   * @dev Sends funds from a vault controlled by the contract.  If the vault
   * is emptied, it will be cleared completely in the storage.
   */
  function sendFromVault (uint vaultId, string memory recipient, uint amount)
      internal
  {
    require (amount > 0, "trying to send zero amount");

    VaultData memory data = vaults[vaultId];
    require (data.balance >= amount, "not enough funds in vault");

    string memory mv
        = config.sendFromVaultMove (account, vaultId, recipient,
                                    data.asset, amount);
    sendGameMove (mv);

    emit SentFromVault (account, vaultId, recipient, data.asset, amount);

    uint newBalance = data.balance - amount;
    emit VaultChanged (account, vaultId, data.asset, newBalance);

    if (newBalance > 0)
      vaults[vaultId].balance = newBalance;
    else
      {
        delete vaults[vaultId];
        emit VaultEmptied (account, vaultId);
      }
  }

  /**
   * @dev Sends a move with the owned account, wrapping it into
   * {"g":{"game id": ... }} for the config's game ID.
   */
  function sendGameMove (string memory mv) private
  {
    string memory gameId = JsonUtils.escapeString (config.gameId ());
    string memory fullMove
        = string (abi.encodePacked ("{\"g\":{", gameId, ":", mv, "}}"));
    sendMove (fullMove);
  }

}