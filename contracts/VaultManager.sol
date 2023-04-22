// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "./AccountHolder.sol";
import "./IDemocritConfig.sol";
import "./JsonUtils.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev This is a contract that manages a set of trading vaults in a
 * Democrit application.  It keeps track of each vault's state as it should
 * be inside the GSP, with the only unknown bit being whether or not the
 * vault was created at all (due to not knowing the real GSP state on chain).
 *
 * The contract is an AccountHolder, with the owned account acting as
 * controller for the vaults.  Vaults can be created (and funded in the
 * same transaction), and assets can be sent from vaults to arbitrary users.
 *
 * This contract is deployed stand-alone, but access to write methods (creating
 * vaults and transferring assets from vaults) is restricted to the "owner".
 * This owner will in production be the Democrit trading contract, which
 * utilises the vaults and triggers vault actions.  Note that in contrast
 * to many smart contracts, this "ownership" does not mean that anyone
 * (including the Xaya team) has any special access to user funds!
 */
contract VaultManager is AccountHolder, Ownable
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

  /** @dev All checkpointed blocks we have seen in the contract.  */
  mapping (bytes32 => bool) private checkpoints;

  /**
   * @dev The lowest block height of a vault that has been created but
   * not yet checkpointed.  Creating vaults auto-triggers checkpointing
   * if there are such vaults, so there will only be exactly one such block
   * height anyway (if at all).  Because if another vault is created at a
   * later height, it will trigger checkpointing of the vaults at the
   * previous heights.  Zero if none such vaults exist.
   */
  uint public uncheckpointedHeight;

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

  /** @dev Emitted when a block hash is checkpointed.  */
  event CheckpointCreated (bytes32 hash);

  constructor (XayaDelegation del, IDemocritConfig cfg)
    AccountHolder(del)
  {
    config = cfg;

    /* We want vault IDs to start at 1, so that a zero ID can be taken
       to mean some entry does not exist.  Thus we add an empty vault at
       index zero.  */
    vaults.push ();
  }

  /**
   * @dev Returns the number of vaults that have been created (even if some
   * of them might have been emptied in the mean time).
   */
  function getNumVaults () public view returns (uint)
  {
    /* The vault at index zero is a dummy one created in the constructor
       and empty right away, we do not want to count it here.  */
    return vaults.length - 1;
  }

  /**
   * @dev Returns the ID given to the next created vault.
   */
  function getNextVaultId () public view returns (uint)
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
      public onlyOwner returns (uint)
  {
    require (config.isTradableAsset (asset), "invalid asset for vault");
    require (initialBalance > 0, "initial balance must be positive");

    /* Trigger automatic checkpointing, and afterwards mark the current height
       as having a new vault.  */
    maybeCreateCheckpoint ();
    uncheckpointedHeight = block.number;

    uint vaultId = getNextVaultId ();
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
      public onlyOwner
  {
    require (amount > 0, "trying to send zero amount");

    VaultData memory data = vaults[vaultId];
    require (data.balance >= amount, "not enough funds in vault");

    /* Trigger automatic checkpointing after the most basic checks
       (so we don't waste gas in case those revert).  */
    maybeCreateCheckpoint ();

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
   * @dev Checks if the given address is the owner or authorised for
   * the account name specified.  This is a helper method that is used to
   * verify the link between (mostly) _msgSender() and accounts from Democrit,
   * since accounts are the main entities used for ownership of vaults
   * and orders.
   */
  function hasAccountPermission (address operator, string memory name)
      public view returns (bool)
  {
    uint256 tokenId = accountRegistry.tokenIdForName ("p", name);
    address owner = accountRegistry.ownerOf (tokenId);
    return operator == owner
        || accountRegistry.isApprovedForAll (owner, operator)
        || accountRegistry.getApproved (tokenId) == operator;
  }

  /**
   * @dev Returns the current owner of the given account name.  This is
   * a helper method used by Democrit.  The owner is for instance who
   * receives ERC-20 tokens when a limit sell order is executed.
   */
  function getAccountAddress (string memory name)
      public view returns (address)
  {
    return accountRegistry.ownerOf (accountRegistry.tokenIdForName ("p", name));
  }

  /**
   * @dev Returns true if the given block hash is known as checkpoint.
   */
  function isCheckpoint (bytes32 hash) public view returns (bool)
  {
    return checkpoints[hash];
  }

  /**
   * @dev If there are any uncheckpointed vaults, trigger a checkpoint.
   * Note that creating a checkpoint is not security critical, so this
   * is a method that anyone is allowed to call any time they want, if
   * they are willing to pay for the gas.  The only thing perhaps bad that
   * could happen is that it triggers a move and the move costs the contract
   * WCHI; but also that will only ever be the case if there are actually
   * vaults to checkpoint, in which case the move is reasonable, and this
   * behaviour cannot be spammed either.
   */
  function maybeCreateCheckpoint () public
  {
    uint h = uncheckpointedHeight;
    if (h == 0 || h >= block.number)
      return;

    uint num = block.number - 1;
    bytes32 cpHash = blockhash (num);

    sendGameMove (config.checkpointMove (account, num, cpHash));
    checkpoints[cpHash] = true;

    uncheckpointedHeight = 0;
    emit CheckpointCreated (cpHash);
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
