// SPDX-License-Identifier: MIT
// Copyright (C) 2023 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const JsonUtilsTestHelper = artifacts.require ("JsonUtilsTestHelper");

contract ("JsonUtils", accounts => {
  let ju;
  before (async () => {
    ju = await JsonUtilsTestHelper.new ();
  });

  it ("escapes valid UTF-8 strings as JSON", async () => {
    const tests = [
      "",
      "foo\0bar",
      "abc\ndef",
      "äöü",
      "🌍",
      "\"foo\"",
      "abc\\\"",
      "\x01\x02\x03\x04\x05\x06\x07\x08\x09",
      "\x0a\x0b\x0c\x0d\x0e\x0f",
    ];

    for (const t of tests)
      {
        const escaped = await ju.escapeString (t);
        const recovered = JSON.parse (escaped);
        assert.equal (recovered, t);
      }
  });

  it ("produces invalid literals for invalid UTF-8", async () => {
    const invalidBytes = [
      "0xff",
      "0xc080",
      "0x2fc0ae2e2f",
    ];

    for (const t of invalidBytes)
      await truffleAssert.reverts (ju.escapeBytes (t));
  });

});
