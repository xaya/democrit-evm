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
  assertFieldIsNull,
  testTrade,
  testVaultCreated,
  testVaultChanged,
  testVaultEmptied,
  testSellOrderCreated,
  testSellOrderUpdated,
  testSellOrderRemoved,
  testPoolCreated,
  testPoolUpdated,
  testPoolRemoved,
  testDepositCreated,
  testDepositUpdated,
  testDepositRemoved,
  testBuyOrderCreated,
  testBuyOrderUpdated,
  testBuyOrderRemoved,
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
    assertFieldIsNull ("Vault", "101", "tradingPool")
    assertFieldIsNull ("Vault", "101", "sellDeposit")
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
    testSellOrderCreated (2, 200, ADDRESS1, "seller", "silver", 100, 10)
    testSellOrderRemoved (2)

    assert.fieldEquals ("SellOrder", "1", "asset", "gold")
    assert.notInStore ("SellOrder", "2")
  })
})

describe ("TradingPools", () => {
  test ("Creation", () => {
    testPoolCreated (10, "pool", "endpoint", "gold", 10, 5)
    testPoolCreated (20, "pool", "", "silver", 100, 0)

    assert.fieldEquals ("TradingPool", "10", "operator", "pool")
    assert.fieldEquals ("TradingPool", "10", "endpoint", "endpoint")
    assert.fieldEquals ("TradingPool", "10", "asset", "gold")
    assert.fieldEquals ("TradingPool", "10", "balance", "10")
    assert.fieldEquals ("TradingPool", "10", "relFee", "5")

    assert.fieldEquals ("TradingPool", "20", "operator", "pool")
    assertFieldIsNull ("TradingPool", "20", "endpoint")
    assert.fieldEquals ("TradingPool", "20", "asset", "silver")
    assert.fieldEquals ("TradingPool", "20", "balance", "100")
    assert.fieldEquals ("TradingPool", "20", "relFee", "0")
  })

  test ("Link to vault", () => {
    testVaultCreated (101, "domob", "gold", 10)
    testPoolCreated (101, "pool", "", "gold", 10, 5)

    assertFieldIsNull ("Vault", "101", "sellOrder")
    assert.fieldEquals ("Vault", "101", "tradingPool", "101")
    assertFieldIsNull ("Vault", "101", "sellDeposit")
    assert.fieldEquals ("TradingPool", "101", "vault", "101")
  })

  test ("Update", () => {
    testPoolCreated (1, "pool", "", "gold", 10, 5)
    testPoolUpdated (1, 2)

    assert.fieldEquals ("TradingPool", "1", "balance", "2")
  })

  test ("Removal", () => {
    testPoolCreated (1, "pool", "", "gold", 10, 5)
    testPoolCreated (2, "pool", "", "silver", 100, 10)
    testPoolRemoved (2)

    assert.fieldEquals ("TradingPool", "1", "asset", "gold")
    assert.notInStore ("TradingPool", "2")
  })
})

describe ("SellDeposit", () => {
  test ("Creation", () => {
    testDepositCreated (10, "seller", "gold", 10)
    testDepositCreated (20, "seller", "silver", 100)

    assert.fieldEquals ("SellDeposit", "10", "owner", "seller")
    assert.fieldEquals ("SellDeposit", "10", "asset", "gold")
    assert.fieldEquals ("SellDeposit", "10", "balance", "10")

    assert.fieldEquals ("SellDeposit", "20", "owner", "seller")
    assert.fieldEquals ("SellDeposit", "20", "asset", "silver")
    assert.fieldEquals ("SellDeposit", "20", "balance", "100")
  })

  test ("Link to vault", () => {
    testVaultCreated (101, "domob", "gold", 10)
    testDepositCreated (101, "domob", "gold", 10)

    assertFieldIsNull ("Vault", "101", "sellOrder")
    assertFieldIsNull ("Vault", "101", "tradingPool")
    assert.fieldEquals ("Vault", "101", "sellDeposit", "101")
    assert.fieldEquals ("SellDeposit", "101", "vault", "101")
  })

  test ("Update", () => {
    testDepositCreated (1, "seller", "gold", 10)
    testDepositUpdated (1, 7)

    assert.fieldEquals ("SellDeposit", "1", "balance", "7")
  })

  test ("Removal", () => {
    testDepositCreated (1, "seller", "gold", 10)
    testDepositCreated (2, "seller", "silver", 100)
    testDepositRemoved (2)

    assert.fieldEquals ("SellDeposit", "1", "asset", "gold")
    assert.notInStore ("SellDeposit", "2")
  })
})

describe ("BuyOrders", () => {
  test ("Creation", () => {
    testBuyOrderCreated (10, 110, ADDRESS1, "buyer", "gold", 10, 200)
    testBuyOrderCreated (20, 120, ADDRESS2, "buyer", "silver", 100, 50)

    assert.fieldEquals ("BuyOrder", "10", "tradingPool", "110")
    assert.fieldEquals ("BuyOrder", "10", "creator", ADDRESS1.toHexString ())
    assert.fieldEquals ("BuyOrder", "10", "buyer", "buyer")
    assert.fieldEquals ("BuyOrder", "10", "asset", "gold")
    assert.fieldEquals ("BuyOrder", "10", "amount", "10")
    assert.fieldEquals ("BuyOrder", "10", "totalSats", "200")
    assert.fieldEquals ("BuyOrder", "10", "price", "20")

    assert.fieldEquals ("BuyOrder", "20", "tradingPool", "120")
    assert.fieldEquals ("BuyOrder", "20", "creator", ADDRESS2.toHexString ())
    assert.fieldEquals ("BuyOrder", "20", "asset", "silver")
    assert.fieldEquals ("BuyOrder", "20", "amount", "100")
    assert.fieldEquals ("BuyOrder", "20", "totalSats", "50")
    assert.fieldEquals ("BuyOrder", "20", "price", "0.5")
  })

  test ("Update", () => {
    testBuyOrderCreated (1, 100, ADDRESS1, "buyer", "gold", 10, 5)
    testBuyOrderUpdated (1, 5, 1)

    assert.fieldEquals ("BuyOrder", "1", "amount", "5")
    assert.fieldEquals ("BuyOrder", "1", "totalSats", "1")
    assert.fieldEquals ("BuyOrder", "1", "price", "0.2")
  })

  test ("Removal", () => {
    testBuyOrderCreated (1, 100, ADDRESS1, "buyer", "gold", 10, 5)
    testBuyOrderCreated (2, 200, ADDRESS1, "buyer", "silver", 100, 10)
    testBuyOrderRemoved (2)

    assert.fieldEquals ("BuyOrder", "1", "asset", "gold")
    assert.notInStore ("BuyOrder", "2")
  })
})
