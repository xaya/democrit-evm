import { newMockEvent } from "matchstick-as/assembly/index"
import { Address, ethereum } from "@graphprotocol/graph-ts"

import {
  Trade as TradeEvent,
  SellOrderCreated as SellOrderCreatedEvent,
  SellOrderUpdated as SellOrderUpdatedEvent,
  SellOrderRemoved as SellOrderRemovedEvent,
  PoolCreated as PoolCreatedEvent,
  PoolUpdated as PoolUpdatedEvent,
  PoolRemoved as PoolRemovedEvent,
  SellDepositCreated as SellDepositCreatedEvent,
  SellDepositUpdated as SellDepositUpdatedEvent,
  SellDepositRemoved as SellDepositRemovedEvent,
  BuyOrderCreated as BuyOrderCreatedEvent,
  BuyOrderUpdated as BuyOrderUpdatedEvent,
  BuyOrderRemoved as BuyOrderRemovedEvent,
} from "../generated/Democrit/Democrit"

import {
  VaultCreated as VaultCreatedEvent,
  VaultChanged as VaultChangedEvent,
  VaultEmptied as VaultEmptiedEvent,
} from "../generated/VaultManager/VaultManager"

import {
  handleTrade,
  handleVaultCreated,
  handleVaultChanged,
  handleVaultEmptied,
  handleSellOrderCreated,
  handleSellOrderUpdated,
  handleSellOrderRemoved,
  handlePoolCreated,
  handlePoolUpdated,
  handlePoolRemoved,
  handleDepositCreated,
  handleDepositUpdated,
  handleDepositRemoved,
  handleBuyOrderCreated,
  handleBuyOrderUpdated,
  handleBuyOrderRemoved,
} from "../src/democrit"

import { BigInt, ValueKind, store } from "@graphprotocol/graph-ts"

export const ADDRESS1: Address
    = Address.fromString ("0xabababababababababababababababababababab")
export const ADDRESS2: Address
    = Address.fromString ("0xfefefefefefefefefefefefefefefefefefefefe")

export function assertFieldIsNull (entityType: string, id: string,
                                   field: string): void
{
  let entity = store.get (entityType, id)
  if (!entity)
    throw new Error ("Entity does not exist")
  let value = entity.get (field)
  if (!value || value.kind == ValueKind.NULL)
    return
  throw new Error ("Expected field to be null, but it isn't")
}

/* ************************************************************************** */

export function testTrade (time: i32, asset: string, amount: i32, sats: i32,
                           seller: string, buyer: string): void
{
  let t = changetype<TradeEvent> (newMockEvent ())
  t.block.timestamp = BigInt.fromI32 (time)
  t.parameters = new Array ()
  t.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString (asset)))
  t.parameters.push (
      new ethereum.EventParam ("amount", ethereum.Value.fromI32 (amount)))
  t.parameters.push (
      new ethereum.EventParam ("sats", ethereum.Value.fromI32 (sats)))
  t.parameters.push (
      new ethereum.EventParam ("seller", ethereum.Value.fromString (seller)))
  t.parameters.push (
      new ethereum.EventParam ("buyer", ethereum.Value.fromString (buyer)))
  handleTrade (t)
}

/* ************************************************************************** */

export function testVaultCreated (vaultId: i32, founder: string,
                                  asset: string, initialBalance: i32): void
{
  let v = changetype<VaultCreatedEvent> (newMockEvent ())
  v.parameters = new Array ();
  v.parameters.push (
      new ethereum.EventParam ("controller", ethereum.Value.fromString ("foo")))
  v.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  v.parameters.push (
      new ethereum.EventParam ("founder", ethereum.Value.fromString (founder)))
  v.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString (asset)))
  v.parameters.push (
      new ethereum.EventParam ("initialBalance",
                               ethereum.Value.fromI32 (initialBalance)))
  handleVaultCreated (v)
}

export function testVaultChanged (vaultId: i32, balance: i32): void
{
  let v = changetype<VaultChangedEvent> (newMockEvent ())
  v.parameters = new Array ();
  v.parameters.push (
      new ethereum.EventParam ("controller", ethereum.Value.fromString ("foo")))
  v.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  v.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString ("ignored")))
  v.parameters.push (
      new ethereum.EventParam ("balance", ethereum.Value.fromI32 (balance)))
  handleVaultChanged (v)
}

export function testVaultEmptied (vaultId: i32): void
{
  let v = changetype<VaultEmptiedEvent> (newMockEvent ())
  v.parameters = new Array ();
  v.parameters.push (
      new ethereum.EventParam ("controller", ethereum.Value.fromString ("foo")))
  v.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  handleVaultEmptied (v)
}

/* ************************************************************************** */

export function testSellOrderCreated (orderId: i32, vaultId: i32,
                                      creator: Address, seller: string,
                                      asset: string,
                                      amount: i32, sats: i32): void
{
  let o = changetype<SellOrderCreatedEvent> (newMockEvent ())
  o.parameters = new Array ();
  o.parameters.push (
      new ethereum.EventParam ("orderId", ethereum.Value.fromI32 (orderId)))
  o.parameters.push (
      new ethereum.EventParam ("vaultId", ethereum.Value.fromI32 (vaultId)))
  o.parameters.push (
      new ethereum.EventParam ("creator", ethereum.Value.fromAddress (creator)))
  o.parameters.push (
      new ethereum.EventParam ("seller", ethereum.Value.fromString (seller)))
  o.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString (asset)))
  o.parameters.push (
      new ethereum.EventParam ("amount", ethereum.Value.fromI32 (amount)))
  o.parameters.push (
      new ethereum.EventParam ("totalSats", ethereum.Value.fromI32 (sats)))
  handleSellOrderCreated (o);
}

export function testSellOrderUpdated (orderId: i32,
                                      amount: i32, sats: i32): void
{
  let o = changetype<SellOrderUpdatedEvent> (newMockEvent ())
  o.parameters = new Array ();
  o.parameters.push (
      new ethereum.EventParam ("orderId", ethereum.Value.fromI32 (orderId)))
  o.parameters.push (
      new ethereum.EventParam ("amount", ethereum.Value.fromI32 (amount)))
  o.parameters.push (
      new ethereum.EventParam ("totalSats", ethereum.Value.fromI32 (sats)))
  handleSellOrderUpdated (o);
}

export function testSellOrderRemoved (orderId: i32,): void
{
  let o = changetype<SellOrderRemovedEvent> (newMockEvent ())
  o.parameters = new Array ();
  o.parameters.push (
      new ethereum.EventParam ("orderId", ethereum.Value.fromI32 (orderId)))
  handleSellOrderRemoved (o);
}

/* ************************************************************************** */

export function testPoolCreated (vaultId: i32, operator: string,
                                 endpoint: string,
                                 asset: string, amount: i32, relFee: i32): void
{
  let p = changetype<PoolCreatedEvent> (newMockEvent ())
  p.parameters = new Array ();
  p.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  p.parameters.push (
      new ethereum.EventParam ("operator",
                               ethereum.Value.fromString (operator)))
  p.parameters.push (
      new ethereum.EventParam ("endpoint",
                               ethereum.Value.fromString (endpoint)))
  p.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString (asset)))
  p.parameters.push (
      new ethereum.EventParam ("amount",
                               ethereum.Value.fromI32 (amount)))
  p.parameters.push (
      new ethereum.EventParam ("relFee",
                               ethereum.Value.fromI32 (relFee)))
  handlePoolCreated (p)
}

export function testPoolUpdated (vaultId: i32, newAmount: i32): void
{
  let p = changetype<PoolUpdatedEvent> (newMockEvent ())
  p.parameters = new Array ();
  p.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  p.parameters.push (
      new ethereum.EventParam ("newAmount", ethereum.Value.fromI32 (newAmount)))
  handlePoolUpdated (p)
}

export function testPoolRemoved (vaultId: i32): void
{
  let p = changetype<PoolRemovedEvent> (newMockEvent ())
  p.parameters = new Array ();
  p.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  handlePoolRemoved (p)
}

/* ************************************************************************** */

export function testDepositCreated (vaultId: i32, owner: string,
                                    asset: string, amount: i32): void
{
  let d = changetype<SellDepositCreatedEvent> (newMockEvent ())
  d.parameters = new Array ();
  d.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  d.parameters.push (
      new ethereum.EventParam ("owner", ethereum.Value.fromString (owner)))
  d.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString (asset)))
  d.parameters.push (
      new ethereum.EventParam ("amount",
                               ethereum.Value.fromI32 (amount)))
  handleDepositCreated (d)
}

export function testDepositUpdated (vaultId: i32, newAmount: i32): void
{
  let d = changetype<SellDepositUpdatedEvent> (newMockEvent ())
  d.parameters = new Array ();
  d.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  d.parameters.push (
      new ethereum.EventParam ("newAmount", ethereum.Value.fromI32 (newAmount)))
  handleDepositUpdated (d)
}

export function testDepositRemoved (vaultId: i32): void
{
  let d = changetype<SellDepositRemovedEvent> (newMockEvent ())
  d.parameters = new Array ();
  d.parameters.push (
      new ethereum.EventParam ("id", ethereum.Value.fromI32 (vaultId)))
  handleDepositRemoved (d)
}

/* ************************************************************************** */

export function testBuyOrderCreated (orderId: i32, poolId: i32,
                                     creator: Address, buyer: string,
                                     asset: string,
                                     amount: i32, sats: i32): void
{
  let o = changetype<BuyOrderCreatedEvent> (newMockEvent ())
  o.parameters = new Array ();
  o.parameters.push (
      new ethereum.EventParam ("orderId", ethereum.Value.fromI32 (orderId)))
  o.parameters.push (
      new ethereum.EventParam ("poolId", ethereum.Value.fromI32 (poolId)))
  o.parameters.push (
      new ethereum.EventParam ("creator", ethereum.Value.fromAddress (creator)))
  o.parameters.push (
      new ethereum.EventParam ("buyer", ethereum.Value.fromString (buyer)))
  o.parameters.push (
      new ethereum.EventParam ("asset", ethereum.Value.fromString (asset)))
  o.parameters.push (
      new ethereum.EventParam ("amount", ethereum.Value.fromI32 (amount)))
  o.parameters.push (
      new ethereum.EventParam ("totalSats", ethereum.Value.fromI32 (sats)))
  handleBuyOrderCreated (o);
}

export function testBuyOrderUpdated (orderId: i32,
                                     amount: i32, sats: i32): void
{
  let o = changetype<BuyOrderUpdatedEvent> (newMockEvent ())
  o.parameters = new Array ();
  o.parameters.push (
      new ethereum.EventParam ("orderId", ethereum.Value.fromI32 (orderId)))
  o.parameters.push (
      new ethereum.EventParam ("amount", ethereum.Value.fromI32 (amount)))
  o.parameters.push (
      new ethereum.EventParam ("totalSats", ethereum.Value.fromI32 (sats)))
  handleBuyOrderUpdated (o);
}

export function testBuyOrderRemoved (orderId: i32,): void
{
  let o = changetype<BuyOrderRemovedEvent> (newMockEvent ())
  o.parameters = new Array ();
  o.parameters.push (
      new ethereum.EventParam ("orderId", ethereum.Value.fromI32 (orderId)))
  handleBuyOrderRemoved (o);
}
