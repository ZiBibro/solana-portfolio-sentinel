---
name: liquidation-price
description: Turn the liquidation buffer percentage into the SOL price at which the position gets liquidated, using the built-in http tool
version: 1.0.0
author: ZiBibro
tags: [solana, defi, pricing]
---

# Liquidation price

`lending_health` prints each position as a current LTV against the liquidation
LTV that position is measured against, for example `LTV 63.2% of 72.9% liq`.
The gap between the two is how far the position can fall before liquidation,
and it is a percentage, which is the honest unit for a plugin to report because
it holds regardless of what anything costs today.
An operator, though, thinks in prices. This skill closes that gap without any
compiled code.

## When to use it

Use it when a position comes back `WARN` or `CRITICAL` and the operator asks what
price would put them in trouble. Skip it for a position marked `no debt`, which
has no liquidation price, and skip it for `UNKNOWN`, where the buffer itself is
not established.

**The report does not name the collateral asset, and this conversion only holds
for collateral that moves with SOL.** `lending_health` prints the protocol, the
market, the position id and the two LTV figures; it prints no mint and no symbol.
So do not infer the collateral. Ask the operator which asset backs the position
before converting, in one short question, and convert only once they have said
SOL or an SOL liquid-staking token. If they say a stablecoin or a mixed basket,
or if they do not answer, report the buffer as a percentage and say the price
conversion does not apply to that collateral.

Do not run it on every position in a healthy report. It costs a network call and
answers a question nobody asked.

## How

Use the built-in `http_request` tool. This deliberately does not go through a
plugin: it is one GET and some arithmetic, which is exactly the work that
belongs at tier 1. Compiling it into WebAssembly would buy nothing and cost the
operator a rebuild.

**That tool is granted in interactive sessions, not in the scheduled brief.** The
documented cron job narrows its run to the two readers, so `http_request` is not
callable there and this skill cannot complete during it. That is the intended
shape: an unattended job stays read-only over the operator's own accounts. If
the tool is unavailable, report the buffer as a percentage and stop, exactly as
under a failed price lookup below.

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

The report gives two LTV figures, not a buffer. Derive the buffer from them:

```
buffer = (liquidation LTV − current LTV) / liquidation LTV
liquidation price = current price × (1 − buffer)
```

The division matters. Subtracting the two percentages gives the gap in
percentage points, which is a different number and always the smaller one, so
using it puts the liquidation price too high and reports the position as safer
than it is.

Worked: `LTV 63.2% of 72.9% liq` gives `(72.9 − 63.2) / 72.9 = 0.133`. With SOL
at 72.90 that is `72.90 × 0.867 = 63.20`. Report it as a price and as a
distance: "liquidation around $63.20, which is 13.3% below where SOL is now."
The bare subtraction would have given 9.7% and a price of $65.83.

Round to cents. Do not present more precision than the inputs carry, and say the
number is approximate, because the buffer was computed against a report that is
already some minutes old.

## What this does not do

It does not predict anything and it is not advice. It converts one unit into
another so the operator can compare a position against a price they already have
a feeling for.

It assumes the collateral moves with SOL, and the report cannot confirm that, so
the operator's answer is what licenses the conversion. Without it, a number that
looks precise and means nothing is the worse outcome of the two.

## If the call fails

Say the price lookup failed and report the buffer percentage on its own. The
percentage is the load-bearing number and it came from the chain. The price is
convenience, and a convenience layer must never take down the answer underneath
it.
