---
name: morning-triage
description: How to read the Solana position reports and decide what needs the operator today
version: 1.0.0
author: ZiBibro
tags: [solana, defi, triage]
---

# Morning triage

This is the procedure behind the daily brief. Follow it whenever the operator
asks about their positions, and follow it unprompted when the scheduled job
wakes you.

## Call both readers, in this order

1. `stake_monitor` first. It is the cheaper call and its answer decides whether
   the lending side even matters today: a stake that finished cooling down is
   liquidity the operator can move against a loan.
2. `lending_health` second, for every wallet under watch.

Call each one once. If the operator asks the same question twice in a session,
call again rather than answering from what you already said. The chain moved.

## Read the lending numbers correctly

Each position line carries a current LTV and the liquidation line that belongs
to that position. The number that matters is the distance between them, not the
LTV on its own. A position at 66% is in danger when its line sits at 65%, and a
position at 82% is comfortable when its line sits at 95%. The plugin already
does this arithmetic and hands you a verdict per position. Trust the verdict,
and quote the pair when you explain it.

`no debt` means the position carries collateral and no borrow. That is the
safest state there is. Never describe it as stale, unknown, or unmeasurable.

`UNKNOWN` means a number the verdict depends on could not be read. Say that
plainly. Do not guess a verdict from the figures that did parse, and do not
smooth it over with a reassuring sentence.

A line prefixed `maint LTV` is measured on MarginFi's maintenance-weighted
basis. Its dollar figures are unweighted. Both are correct, and they will not
divide into each other. Say so if the operator does the division and asks.

## Read the stake numbers correctly

The header sums only stake that is actually working for a validator. An account
that finished cooling down keeps its old delegation record on chain and is
excluded on purpose.

A validator commission of 100% with no reward last epoch means the operator is
staking for nothing. Say it directly and name the options.

Vote lag is measured in slots against the operator's own threshold. Lag below
the threshold is not news and does not belong in a brief.

## What to report, and what to leave out

The brief exists to save the operator ten minutes, so it earns its place only by
being short. Lead with what changed since the previous run and what needs a
decision today. When nothing needs action, say that in one line and stop. Resist
the urge to restate healthy positions for completeness: a clean morning is one
line, and that line is the product.

When something does need a decision, name the options without choosing for the
operator. They hold the keys.

## Addresses

Never abbreviate a Solana address, in any message, for any reason. An address
shortened to its visible ends can be matched by an attacker who grinds a
keypair, which turns a verification step into theatre. If a summary arrives with
full addresses, relay them in full even when the message gets long.

## Boundaries you should explain rather than work around

Addresses come from the operator's config allowlist. You can report on fewer of
them when asked. You cannot add one, and the tools will refuse if you try. When
the operator asks about an address that is not in the allowlist, tell them it
needs to go in the config, and tell them which key.

The network is fixed by config as well. There is no cluster argument on any
tool. If asked to check another network, explain that it is a config change and
a restart.

Building a transaction is never part of triage. It happens only when the
operator asks for it, in dialogue, behind an approval card. The scheduled brief
does not have that tool at all.
