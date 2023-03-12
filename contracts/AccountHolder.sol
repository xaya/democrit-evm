// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@xaya/eth-account-registry/contracts/IXayaAccounts.sol";
import "@xaya/eth-delegator-contract/contracts/XayaDelegation.sol";

/**
 * @dev This defines a contract that owns a Xaya account and is able to send
 * moves with it.
 *
 * The account name must be created externally and transferred as ERC-721
 * to the contract.  Once this is done, the name will be locked forever
 * inside the contract.  This transfer will "initialise" the contract.
 */
contract AccountHolder is IERC721Receiver
{

  /** @dev The WCHI token used.  */
  IERC20Metadata public immutable wchi;

  /** @dev The XayaAccounts registry used.  */
  IXayaAccounts public immutable accountRegistry;

  /** @dev The move delegation contract used.  */
  XayaDelegation public immutable delegator;

  /** @dev Set to true when the contract is initialised.  */
  bool public initialised;

  /**
   * @dev The Xaya account name owned by this contract.  This is set on
   * initialisation, i.e. when a name gets transferred to the contract.
   */
  string public account;

  /**
   * @dev Emitted when the contract is initialised, i.e. its Xaya account
   * name gets specified.
   */
  event Initialised (string account);

  /** @dev Emitted whenever a move is sent with the contract's account.  */
  event Move (string mv);

  constructor (XayaDelegation del)
  {
    delegator = del;
    accountRegistry = del.accounts ();
    wchi = IERC20Metadata (address (accountRegistry.wchiToken ()));

    /* We approve WCHI on the accounts registry, to make sure that we can
       send moves that may require fees.  Note that it will be the
       responsibility of someone else to top up this contract's WCHI
       balance as needed to pay for those fees.  WCHI sent to the contract
       will only be spendable on fees, and not be recoverable in any other
       way!  */
    wchi.approve (address (accountRegistry), type (uint256).max);
  }

  /**
   * @dev We accept a single ERC-721 token transfer, of Xaya accounts (no
   * other tokens).  This initialises the contract.
   */
  function onERC721Received (address, address, uint256 tokenId, bytes calldata)
      external override returns (bytes4)
  {
    require (!initialised, "contract is already initialised");
    require (msg.sender == address (accountRegistry),
             "only Xaya names can be received");

    (string memory ns, string memory name)
        = accountRegistry.tokenIdToName (tokenId);
    bytes32 nsAccountHash = keccak256 (abi.encodePacked ("p"));
    require (keccak256 (abi.encodePacked (ns)) == nsAccountHash,
             "only Xaya accounts can be received");

    initialised = true; 
    account = name;
    emit Initialised (name);

    return IERC721Receiver.onERC721Received.selector;
  }

  /**
   * @dev Sends a Xaya move with the owned account.
   */
  function sendMove (string memory mv) internal
  {
    require (initialised, "contract is not initialised");
    accountRegistry.move ("p", account, mv, type (uint256).max, 0, address (0));
    emit Move (mv);
  }

}
