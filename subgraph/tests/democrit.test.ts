import {
  assert,
  afterAll,
  clearStore,
  describe,
  test,
} from "matchstick-as/assembly/index"

import {
  ADDRESS1,
  ADDRESS2,
  testTrade,
  testVaultCreated,
  testVaultChanged,
  testVaultEmptied,
  testSellOrderCreated,
  testSellOrderUpdated,
  testSellOrderRemoved,
} from "./utils"

afterAll (clearStore)

test ("Trades", () => {
  testTrade (123, "gold", 10, 500, "seller", "buyer")
  testTrade (456, "silver", 100, 20, "seller", "buyer")

  assert.fieldEquals ("Trade", "1", "timestamp", "123")
  assert.fieldEquals ("Trade", "1", "asset", "gold")
  assert.fieldEquals ("Trade", "1", "amount", "10")
  assert.fieldEquals ("Trade", "1", "sats", "500")
  assert.fieldEquals ("Trade", "1", "price", "50")
  assert.fieldEquals ("Trade", "1", "seller", "seller")
  assert.fieldEquals ("Trade", "1", "buyer", "buyer")

  assert.fieldEquals ("Trade", "2", "timestamp", "456")
  assert.fieldEquals ("Trade", "2", "asset", "silver")
  assert.fieldEquals ("Trade", "2", "amount", "100")
  assert.fieldEquals ("Trade", "2", "sats", "20")
  assert.fieldEquals ("Trade", "2", "price", "0.2")
})

describe ("Vaults", () => {
  test ("Creation", () => {
    testVaultCreated (42, "domob", "gold", 100)
    testVaultCreated (50, "andy", "silver", 20)

    assert.fieldEquals ("Vault", "42", "founder", "domob")
    assert.fieldEquals ("Vault", "42", "asset", "gold")
    assert.fieldEquals ("Vault", "42", "balance", "100")

    assert.fieldEquals ("Vault", "50", "founder", "andy")
    assert.fieldEquals ("Vault", "50", "asset", "silver")
    assert.fieldEquals ("Vault", "50", "balance", "20")
  })

  test ("Update", () => {
    testVaultCreated (42, "domob", "gold", 100)
    testVaultChanged (42, 50)

    assert.fieldEquals ("Vault", "42", "asset", "gold")
    assert.fieldEquals ("Vault", "42", "balance", "50")
  })

  test ("Emptied", () => {
    testVaultCreated (42, "domob", "gold", 100)
    testVaultCreated (50, "domob", "silver", 20)

    testVaultChanged (42, 0)
    testVaultEmptied (42)

    assert.notInStore ("Vault", "42")
    assert.fieldEquals ("Vault", "50", "asset", "silver")
    assert.fieldEquals ("Vault", "50", "balance", "20")
  })
})

describe ("SellOrders", () => {
  test ("Creation", () => {
    testSellOrderCreated (10, 110, ADDRESS1, "seller", "gold", 10, 200)
    testSellOrderCreated (20, 120, ADDRESS2, "seller", "silver", 100, 50)

    assert.fieldEquals ("SellOrder", "10", "creator", ADDRESS1.toHexString ())
    assert.fieldEquals ("SellOrder", "10", "seller", "seller")
    assert.fieldEquals ("SellOrder", "10", "asset", "gold")
    assert.fieldEquals ("SellOrder", "10", "amount", "10")
    assert.fieldEquals ("SellOrder", "10", "totalSats", "200")
    assert.fieldEquals ("SellOrder", "10", "price", "20")

    assert.fieldEquals ("SellOrder", "20", "creator", ADDRESS2.toHexString ())
    assert.fieldEquals ("SellOrder", "20", "asset", "silver")
    assert.fieldEquals ("SellOrder", "20", "amount", "100")
    assert.fieldEquals ("SellOrder", "20", "totalSats", "50")
    assert.fieldEquals ("SellOrder", "20", "price", "0.5")
  })

  test ("Link to vault", () => {
    testVaultCreated (101, "domob", "gold", 10)
    testSellOrderCreated (1, 101, ADDRESS1, "domob", "gold", 10, 50)

    assert.fieldEquals ("Vault", "101", "sellOrder", "1")
    assert.fieldEquals ("SellOrder", "1", "vault", "101")
  })

  test ("Update", () => {
    testSellOrderCreated (1, 100, ADDRESS1, "seller", "gold", 10, 5)
    testSellOrderUpdated (1, 5, 1)

    assert.fieldEquals ("SellOrder", "1", "amount", "5")
    assert.fieldEquals ("SellOrder", "1", "totalSats", "1")
    assert.fieldEquals ("SellOrder", "1", "price", "0.2")
  })

  test ("Removal", () => {
    testSellOrderCreated (1, 100, ADDRESS1, "seller", "gold", 10, 5)
    testSellOrderCreated (2, 200, ADDRESS1, "seler", "silver", 100, 10)
    testSellOrderRemoved (2)

    assert.fieldEquals ("SellOrder", "1", "asset", "gold")
    assert.notInStore ("SellOrder", "2")
  })
})
