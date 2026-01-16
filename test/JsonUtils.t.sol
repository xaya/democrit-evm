// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.19;

import "../src/JsonUtils.sol";

import { Test } from "forge-std/Test.sol";

contract JsonUtilsTest is Test
{

  /**
   * @dev External helper function that forwards to the library, but allows
   * us to use expectRevert at a lower call depth.
   */
  function escape (string memory input)
      external pure returns (string memory)
  {
    return JsonUtils.escapeString (input);
  }

  /**
   * @dev Helper function that tests a roundtrip of escaping and
   * JSON parsing for a particular string.
   */
  function roundTrip (string memory input) private view
  {
    string memory escaped = this.escape (input);

    /* We use vm.parseJson to validate the generated literal, but this
       expects a JSON object.  Thus we wrap it into one.  */
    string memory json = string.concat ('{"value":', escaped, '}');

    bytes memory data = vm.parseJson (json, ".value");
    string memory decoded = abi.decode (data, (string));

    assertEq (decoded, input);
  }

  /**
   * @dev Helper function that tests that a given bytes string (which is invalid
   * UTF-8) cannot be escaped.
   */
  function invalidUtf8 (bytes memory input) private
  {
    vm.expectRevert ();
    this.escape (string (input));
  }

  function test_validStrings () public view
  {
    roundTrip ("");
    roundTrip ("foo\x00bar");
    roundTrip ("abc\ndef");
    roundTrip (unicode"äöü");
    roundTrip (unicode"🌍");
    roundTrip ("\"foo\"");
    roundTrip ("abc\\\"");
    roundTrip ("\x01\x02\x03\x04\x05\x06\x07\x08\x09");
    roundTrip ("\x0a\x0b\x0c\x0d\x0e\x0f");
  }

  function test_invalidUtf8 () public
  {
    invalidUtf8 (hex"ff");
    invalidUtf8 (hex"c080");
    invalidUtf8 (hex"2fc0ae2e2f");
  }

}
