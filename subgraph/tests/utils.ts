import { newMockEvent } from "matchstick-as/assembly/index"
import { Address, ethereum } from "@graphprotocol/graph-ts"

import {
  Trade as TradeEvent,
  VaultCreated as VaultCreatedEvent,
  VaultChanged as VaultChangedEvent,
  VaultEmptied as VaultEmptiedEvent,
  SellOrderCreated as SellOrderCreatedEvent,
  SellOrderUpdated as SellOrderUpdatedEvent,
  SellOrderRemoved as SellOrderRemovedEvent,
} from "../generated/Democrit/Democrit"

import {
  handleTrade,
  handleVaultCreated,
  handleVaultChanged,
  handleVaultEmptied,
  handleSellOrderCreated,
  handleSellOrderUpdated,
  handleSellOrderRemoved,
} from "../src/democrit"

import { BigInt } from "@graphprotocol/graph-ts"

export const ADDRESS1: Address
    = Address.fromString ("0xabababababababababababababababababababab")
export const ADDRESS2: Address
    = Address.fromString ("0xfefefefefefefefefefefefefefefefefefefefe")

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
