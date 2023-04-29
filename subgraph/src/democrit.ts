import {
  Trade as TradeEvent,
  SellOrderCreated as SellOrderCreatedEvent,
  SellOrderUpdated as SellOrderUpdatedEvent,
  SellOrderRemoved as SellOrderRemovedEvent,
} from "../generated/Democrit/Democrit"

import {
  VaultCreated as VaultCreatedEvent,
  VaultChanged as VaultChangedEvent,
  VaultEmptied as VaultEmptiedEvent,
} from "../generated/VaultManager/VaultManager"

import {
  AutoId,
  Trade,
  Vault,
  SellOrder,
} from "../generated/schema"

import { BigInt, store } from "@graphprotocol/graph-ts"

/* ************************************************************************** */

function getAutoId (series: String): BigInt
{
  let entry = AutoId.load (series)
  if (entry == null)
    {
      entry = new AutoId (series)
      entry.next = BigInt.fromI32 (1)
    }

  let result = entry.next
  entry.next = entry.next + BigInt.fromI32 (1)
  entry.save ()

  return result
}

export function handleTrade (event: TradeEvent): void
{
  let id = getAutoId ("Trade").toString ()
  let trade = new Trade (id)

  trade.timestamp = event.block.timestamp

  trade.asset = event.params.asset
  trade.amount = event.params.amount
  trade.sats = event.params.sats
  trade.price = trade.sats.toBigDecimal () / trade.amount.toBigDecimal ()

  trade.seller = event.params.seller
  trade.buyer = event.params.buyer

  trade.save ()
}

/* ************************************************************************** */

export function handleVaultCreated (event: VaultCreatedEvent): void
{
  let vault = new Vault (event.params.id.toString ())

  vault.founder = event.params.founder
  vault.asset = event.params.asset
  vault.balance = event.params.initialBalance

  vault.save ()
}

export function handleVaultChanged (event: VaultChangedEvent): void
{
  let id = event.params.id.toString ()
  let vault = Vault.load (id)
  if (vault == null)
    return

  vault.balance = event.params.balance
  vault.save ()
}

export function handleVaultEmptied (event: VaultEmptiedEvent): void
{
  let id = event.params.id.toString ()
  store.remove ("Vault", id)
}

/* ************************************************************************** */

export function handleSellOrderCreated (event: SellOrderCreatedEvent): void
{
  let id = event.params.orderId.toString ()
  let vaultId = event.params.vaultId.toString ()
  let order = new SellOrder (id)

  order.creator = event.params.creator
  order.seller = event.params.seller
  order.asset = event.params.asset
  order.amount = event.params.amount
  order.totalSats = event.params.totalSats
  order.price = order.totalSats.toBigDecimal () / order.amount.toBigDecimal ()

  order.vault = vaultId;
  let vault = Vault.load (vaultId);
  if (vault != null)
    {
      vault.sellOrder = id
      vault.save ()
    }

  order.save ()
}

export function handleSellOrderUpdated (event: SellOrderUpdatedEvent): void
{
  let id = event.params.orderId.toString ()
  let order = SellOrder.load (id)
  if (order == null)
    return

  order.amount = event.params.amount
  order.totalSats = event.params.totalSats
  order.price = order.totalSats.toBigDecimal () / order.amount.toBigDecimal ()
  order.save ()
}

export function handleSellOrderRemoved (event: SellOrderRemovedEvent): void
{
  let id = event.params.orderId.toString ()
  store.remove ("SellOrder", id)
}
