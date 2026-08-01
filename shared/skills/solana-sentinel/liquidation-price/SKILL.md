---
name: liquidation-price
description: Turn the liquidation buffer percentage into the SOL price at which the position gets liquidated, using the built-in http tool
version: 1.0.0
author: ZiBibro
tags: [solana, defi, pricing]
---

# Liquidation price

`lending_health` reports how far a position can fall before liquidation, as a
percentage of the distance to its own line. A percentage is the honest unit for
a plugin to report, because it holds regardless of what anything costs today.
An operator, though, thinks in prices. This skill closes that gap without any
compiled code.

## When to use it

Use it when a position comes back `WARN` or `CRITICAL` and its collateral is SOL
or an SOL liquid-staking token, and when the operator asks what price would put
them in trouble. Skip it for a position marked `no debt`, which has no
liquidation price, and skip it for `UNKNOWN`, where the buffer itself is not
established.

Do not run it on every position in a healthy report. It costs a network call and
answers a question nobody asked.

## How

Use the built-in `http_request` tool. This deliberately does not go through a
plugin: it is one GET and some arithmetic, which is exactly the work that
belongs at tier 1. Compiling it into WebAssembly would buy nothing and cost the
operator a rebuild.

```
GET https://lite-api.jup.ag/price/v3?ids=So11111111111111111111111111111111111111112
```

The keyless tier needs no API key and no account. The reply looks like this
(verbatim, 1 August 2026):

```json
{"So11111111111111111111111111111111111111112":{"usdPrice":72.9021695770283,
 "priceChange24h":-0.25293456902463257,"blockId":436579659}}
```

Read `usdPrice`. Ignore the rest unless the operator asks about the 24 hour move.

## The arithmetic

The plugin's buffer is the fraction of collateral value the position can lose
before it reaches its liquidation line. So:

```
liquidation price = current price × (1 − buffer)
```

A position with a 12.5% buffer while SOL trades at 72.90 gets liquidated around
`72.90 × 0.875 = 63.79`. Report it as a price and as a distance: "liquidation
around $63.79, which is 12.5% below where SOL is now."

Round to cents. Do not present more precision than the inputs carry, and say the
number is approximate, because the buffer was computed against a report that is
already some minutes old.

## What this does not do

It does not predict anything and it is not advice. It converts one unit into
another so the operator can compare a position against a price they already have
a feeling for.

It also assumes the collateral moves with SOL. When collateral is a stablecoin,
or a basket, say that the conversion does not apply rather than producing a
number that looks precise and means nothing.

## If the call fails

Say the price lookup failed and report the buffer percentage on its own. The
percentage is the load-bearing number and it came from the chain. The price is
convenience, and a convenience layer must never take down the answer underneath
it.
