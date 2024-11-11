# Copyright (C) 2023-2024 Autonomous Worlds Ltd
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

"""
This Python module contains logic for running the server that signs
vault checks for a trading pool in Democrit-EVM.
"""


from contextlib import contextmanager
import threading

import jsonrpclib
from jsonrpclib.SimpleJSONRPCServer import PooledJSONRPCServer

from eth_account import Account
from eth_account.messages import encode_structured_data


# The EIP712 name and version that is expected from the contract,
# specifying the protocol for vault signatures that this script implements.
EIP712_NAME = "Democrit"
EIP712_VERSION = "1"


class VaultChecker:
  """
  This class is responsible for talking to the GSP and checking if
  a given vault exists and if so, for what checkpoint.  It must be
  subclassed to implement the GSP-specific RPC call for this.
  """

  def __init__ (self, endpoint):
    self.endpoint = endpoint

  @contextmanager
  def withRpc (self):
    """
    Helper method that establishes a JSON-RPC connection to the
    underlying endpoint, managed inside a context.
    """
    rpc = jsonrpclib.ServerProxy (self.endpoint)
    yield rpc

  def check (self, controller, vaultId):
    """
    Subclasses must implement this method to check if the given vault
    (controller/id) exists in the GSP.  If yes, then the method should
    return (True, <0x112233>) with the checkpoint at which it was seen to
    exist.  If no, then it should return (False, None).
    """
    raise RuntimeError ("not implemented")

  def getGspState (self):
    """
    Subclasses must implement this method to return the basic GSP state,
    e.g. with getnullstate.
    """
    raise RuntimeError ("not implemented")


class Signer:
  """
  This class implements the signing of vault checks per the Democrit
  contract's required EIP712 struct.
  """

  def __init__ (self, w3, loadAbi, contractAddr, operator, key):
    self.w3 = w3
    self.chainId = self.w3.eth.chain_id
    self.account = Account.from_key (key)
    self.operator = operator

    self.c = self.w3.eth.contract (abi=loadAbi ("Democrit"),
                                   address=contractAddr)

    vmAddr = self.c.functions.vm ().call ()
    vm = self.w3.eth.contract (abi=loadAbi ("VaultManager"), address=vmAddr)

    configAddr = self.c.functions.config ().call ()
    config = self.w3.eth.contract (abi=loadAbi ("IDemocritConfig"),
                                   address=configAddr)
    self.gameId = config.functions.gameId ().call ()

    contractName = self.c.functions.EIP712_NAME ().call ()
    contractVersion = self.c.functions.EIP712_VERSION ().call ()
    if contractName != EIP712_NAME or contractVersion != EIP712_VERSION:
      raise RuntimeError ("EIP712 name and/or version mismatch")

    if not vm.functions \
        .hasAccountPermission (self.account.address, operator).call ():
      raise RuntimeError ("The given key cannot sign for operator '%s'"
                            % self.operator)

    self.controller = vm.functions.account ().call ()

  def sign (self, vaultId, checkpoint):
    """
    Signs that the given vault has been verified and validated for the
    checkpoint passed in, at the currently-valid nonce.  This function just
    signs without doing the actual verification, so the caller must ensure
    that it has verified before calling here.

    This method returns the signature as bytes.
    """

    nonce = self.c.functions.signatureNonce (self.operator).call ()
    msg = {
      "domain": {
        "name": EIP712_NAME,
        "version": EIP712_VERSION,
        "chainId": self.chainId,
        "verifyingContract": self.c.address,
      },
      "primaryType": "VaultCheck",
      "types": {
        "EIP712Domain": [
          {"name": "name", "type": "string"},
          {"name": "version", "type": "string"},
          {"name": "chainId", "type": "uint256"},
          {"name": "verifyingContract", "type": "address"},
        ],
        "VaultCheck": [
          {"name": "vaultId", "type": "uint256"},
          {"name": "checkpoint", "type": "bytes32"},
          {"name": "nonce", "type": "uint256"},
        ],
      },
      "message": {
        "vaultId": vaultId,
        "checkpoint": self.w3.to_bytes (hexstr=checkpoint),
        "nonce": nonce,
      },
    }

    encoded = encode_structured_data (msg)
    signed = self.account.sign_message (encoded)

    return signed.signature


class VaultCheckServer:
  """
  This class represents a JSON-RPC server that can be run on request in
  a context.  The server provides a method where callers can request a check
  on a given vault, and if the check is successful, will receive the vault
  signature.
  """

  def __init__ (self, checker, signer):
    self.checker = checker
    self.signer = signer

    # Rough sanity check that the "right" GSP is connected.  Of course, it
    # could still be a wrong version.  The chain most likely needs not be
    # compared, since the checkpoint returned by the GSP is only valid
    # on a particular chain and branch anyway.
    if self.checker.getGspState ()["gameid"] != self.signer.gameId:
      raise RuntimeError ("game ID mismatch")

    def signVaultCheck (vaultId):
      valid, checkpoint = self.checker.check (self.signer.controller, vaultId)
      if (not valid) or checkpoint is None:
        raise RuntimeError ("the requested vault is not valid")
      signature = self.signer.sign (vaultId, checkpoint)
      return {
        "vaultcheck": {
          "vaultId": vaultId,
          "checkpoint": checkpoint,
        },
        "signature": signature.hex (),
      }
    self.signVaultCheck = signVaultCheck

    def getInfo ():
      gsp = self.checker.getGspState ()
      return {
        "gsp": gsp,
        "democrit": {
          "chainid": self.signer.chainId,
          "gameid": self.signer.gameId,
          "contract": self.signer.c.address,
          "controller": self.signer.controller,
        },
        "pool": {
          "operator": self.signer.operator,
          "signer": self.signer.account.address,
        },
      }
    self.getInfo = getInfo

  @contextmanager
  def run (self, bind):
    """
    Runs the server on the given (host, port) in a context.  When the context
    is over, the server will be stopped.
    """

    server = PooledJSONRPCServer (bind)
    server.register_function (self.signVaultCheck, "signvaultcheck")
    server.register_function (self.getInfo, "getinfo")

    runner = threading.Thread (target=server.serve_forever)
    runner.start ()

    try:
      yield
    finally:
      server.shutdown ()
      runner.join ()
