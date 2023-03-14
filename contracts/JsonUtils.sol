// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @dev A basic utility library for dealing with JSON (which we need for
 * handling moves).  In particular, it supports escaping user-provided
 * account names into JSON literals, so we can use them in moves to send
 * assets to those accounts.
 */
library JsonUtils
{

  bytes16 private constant HEX = "0123456789abcdef";

  /**
   * @dev Escapes a raw string into a JSON literal representing the same
   * string (including the surrounding quotes).  If the provided string is
   * invalid UTF-8, then this method will produce invalid UTF-8 as well,
   * so the result will be seen as invalid JSON.
   */
  function escapeString (string memory input)
      internal pure returns (string memory)
  {
    bytes memory data = bytes (input);

    /* Most characters get translated literally (i.e. just copied over).
       We escape " and \ by placing a backslash before them, and change
       control characters to \uXXXX.  So worst case (if all are control
       characters), we 6x the length of the data.  Plus two quotes.  */
    bytes memory out = new bytes (2 + 6 * data.length);

    uint len = 0;
    out[len++] = '"';

    for (uint i = 0; i < data.length; ++i)
      {
        if (data[i] < 0x20)
          {
            out[len++] = '\\';
            out[len++] = 'u';
            out[len++] = '0';
            out[len++] = '0';
            uint8 val = uint8 (data[i]);
            out[len++] = HEX[val >> 4];
            out[len++] = HEX[val & 0xF];
          }
        else if (data[i] == '"' || data[i] == '\\')
          {
            out[len++] = '\\';
            out[len++] = data[i];
          }
        else
          out[len++] = data[i];
      }

    out[len++] = '"';

    assembly {
      mstore (out, len)
    }

    return string (out);
  }

}
