// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@xaya/eth-account-registry/contracts/HexEscapes.sol";
import "@xaya/eth-account-registry/contracts/Utf8.sol";

/**
 * @dev A basic utility library for dealing with JSON (which we need for
 * handling moves).  In particular, it supports escaping user-provided
 * account names into JSON literals, so we can use them in moves to send
 * assets to those accounts.
 */
library JsonUtils
{

  /**
   * @dev Escapes a raw string into a JSON literal representing the same
   * string (including the surrounding quotes).  If the provided string is
   * invalid UTF-8, then this method will revert.
   */
  function escapeString (string memory input)
      internal pure returns (string memory)
  {
    bytes memory data = bytes (input);

    /* ASCII characters get translated literally (i.e. just copied over).
       We escape " and \ by placing a backslash before them, and change
       control characters as well as non-ASCII Unicode codepoints to \uXXXX.
       So worst case, if all are Unicode codepoints that need a
       UTF-16 surrogate pair, we 12x the length of the data, plus
       two quotes.  */
    bytes memory out = new bytes (2 + 12 * data.length);

    uint len = 0;
    out[len++] = '"';

    /* Note that one could in theory ignore the UTF-8 parsing here, and just
       literally copy over bytes 0x80 and above.  This would also produce a
       valid JSON result (or invalid JSON if the input is invalid), but it
       fails the XayaPolicy move validation, which requires all non-ASCII
       characters to be escaped in moves.  */

    uint offset = 0;
    while (offset < data.length)
      {
        uint32 cp;
        (cp, offset) = Utf8.decodeCodepoint (data, offset);
        if (cp == 0x22 || cp == 0x5C)
          {
            out[len++] = '\\';
            out[len++] = bytes1 (uint8 (cp));
          }
        else if (cp >= 0x20 && cp < 0x7F)
          out[len++] = bytes1 (uint8 (cp));
        else
          {
            bytes memory escape = bytes (HexEscapes.jsonCodepoint (cp));
            for (uint i = 0; i < escape.length; ++i)
              out[len++] = escape[i];
          }
      }
    assert (offset == data.length);

    out[len++] = '"';

    assembly {
      mstore (out, len)
    }

    return string (out);
  }

}
