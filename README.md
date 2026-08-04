# solana-portfolio-sentinel

[![CI](https://github.com/ZiBibro/solana-portfolio-sentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/ZiBibro/solana-portfolio-sentinel/actions/workflows/ci.yml)

**Reviewing this? Two minutes gets you the code side of the claim.** Clone, then:

```bash
for m in plugins/*/Cargo.toml; do cargo test --locked --manifest-path "$m"; done
```

211 tests and no wasm toolchain needed. The tests themselves reach no network;
cargo still fetches the pinned dependencies once. Timed on a fresh clone on
3 August 2026: 61 seconds from `git clone` to the last green line, on cargo
1.97.1 rather than the 1.96.1 the CI pins. What a live run prints is in
[What a run looks like](#what-a-run-looks-like) below, taken from the trace
copied out of the trace. The full setup path is [`REPRODUCE.md`](REPRODUCE.md),
[`SHOWCASE.md`](SHOWCASE.md) is the write-up with the custody tier, threat model
and honest limits, and [`shared/`](shared/) is the composition that makes it a
daily habit instead of a library.

**Watch it run (2:11):** https://www.youtube.com/watch?v=nRbTZSxMAQg

**Where this sits in the field, counted.** Measured
2026-08-03 against all 109 open pull requests in `zeroclaw-labs/zeroclaw-plugins`
and the 31 plugins already in the registry:

| question | count |
|---|---|
| Open PRs touching lending health or stake reading | 7 |
| Of those, any that builds a stake `delegate` or `deactivate` transaction | 0 |
| Open PRs that mention composition around the components (cron, skill, SOP) | 9 |

So the reading side is a crowded niche and this submission says so. The claim it
does make is narrower and checkable: the unsigned stake transaction builder has
no counterpart among the open PRs, and the nearest neighbour by craft is
[#151](https://github.com/zeroclaw-labs/zeroclaw-plugins/pull/151), which parses transactions where this one builds them. The other overlap worth naming is
[#104](https://github.com/zeroclaw-labs/zeroclaw-plugins/pull/104), which also
returns unsigned transactions, for Kamino repayments where this one covers stake.

---

ZeroClaw tool plugins that let an agent watch a Solana portfolio and hand back
an unsigned transaction when something needs doing. Two of them read: how close
a DeFi borrow position sits to liquidation, and what the operator's own stake
accounts are doing. The third builds a delegate or deactivate transaction that
stays inert until a human signs it somewhere else.

Nothing here signs or submits, and no private key ever appears in config or
code. Every address a tool touches comes from an operator-owned allowlist,
never from the model.

Each plugin is a self-contained `wasm32-wasip2` component: a pure Rust core the
host test suite exercises without a wasm toolchain, and a thin
`#[cfg(target_family = "wasm")]` shim over the `zeroclaw:plugin@0.1.0` world.

**The components are half of it.** [`shared/`](shared/) holds the composition
that turns them into something someone runs daily: a declarative cron job that
announces a brief every morning with a read-only tool grant, two skills carrying
the reading rules and the price conversion, and one SOP that stops at a human
checkpoint before any transaction bytes exist. Copy that directory into your
install root and point the config at it;
[`shared/README.md`](shared/README.md) explains each piece and why it sits at
that layer. The full runbook is [`REPRODUCE.md`](REPRODUCE.md).

## The readers

### lending-health

Reads Kamino positions from the public Kamino REST API and decodes MarginFi
positions from on-chain account state via `getProgramAccounts`, at the byte
offsets where the program keeps its maintenance-weighted health cache. Each
position is classified against operator-set thresholds on the liquidation
buffer, the share of the distance to its own liquidation line that a position
still has left, which is the quantity Kamino documents as the one that matters.
A position whose basis is missing or unusable is reported as UNKNOWN, and one
with no debt is reported as such, so no verdict is issued without a measurement
behind it. Each line names the obligation it came from.

When MarginFi's maintenance pair is absent, the report states that no
liquidation distance is available instead of computing one on a basis it cannot
justify. When the program's own HEALTHY bit is clear and the engine status bit
shows the cache was actually written, that position leads the report as
CRITICAL. The whole payload is capped, so a recurring briefing never floods the
agent's context window.

### stake-monitor

Per allowlisted stake account: delegation lifecycle status, stake amount,
validator delinquency, vote lag in slots against an operator-set threshold,
epoch progress, and the previous epoch's reward. Delinquency is fetched with a
server-side `votePubkey` filter rather than by pulling the full validator
roster. Commission is read from `inflationRewardsCommissionBps`, because the
legacy `commission` field can come back null.

Vote lag is the early warning: a validator drifting behind the head shows up
here before it is formally delinquent. If the epoch reply is unusable, those two
readings degrade to unknown and every other line still renders.

## The builder

### stake-tx-build

Encodes legacy messages by hand (header bytes, compact-u16 lengths, bincode
discriminants, account metas) with no `solana-sdk` dependency. The reason is
size and auditability rather than capability: the modular Solana crates do
compile to `wasm32-wasip2`, and a component pulling them in still builds, so the
hand-rolled path is a choice to keep the component minimal and every byte
traceable to a test. The instruction bytes are locked by a golden test that
reproduces a live mainnet delegate transaction byte for byte.

Before building anything it verifies the endpoint's genesis hash against the
operator's pinned cluster and refuses on mismatch, so an honest endpoint pointed
at the wrong network cannot produce a transaction the operator believes is for
mainnet. Delegation stays disabled until the operator opts in by listing vote
accounts. With an optional durable-nonce pair configured, the transaction opens
with `AdvanceNonceAccount` and survives a slow approval queue; without one, the
summary states the roughly 60 to 90 second blockhash window.

## What a run looks like

Verbatim from the tools, copied out of the trace. This is the payload the model is handed;
what reaches the chat is its rendering of it. Captured from the morning brief the
cron job fired on its own at 08:00 Europe/Kiev on 4 August 2026.

```
Lending health: 7 position(s), worst risk WARN.
[WARN] main kamino Vanilla@7u3H #HcrU..iS4J: deposit $84055, borrow $60092, LTV 71.5% of 79.9% liq (positions stale 24 h)
[WARN] main kamino Multiply@47tf #FWjx..Vq67: deposit $52273, borrow $34183, LTV 65.4% of 75.0% liq (positions stale 24 h)
[WARN] main kamino Vanilla@47tf #6FJt..SSLy: deposit $148455, borrow $96703, LTV 65.1% of 75.0% liq (positions stale 24 h)
[UNKNOWN] hedge marginfi acct #EN1W..K7ND: deposit $860, borrow $668, LTV n/a (maint basis unavailable)
[OK] own kamino Vanilla@7u3H #62W5..imgq: deposit $22, borrow $5, LTV 22.6% of 75.0% liq (positions stale 56 h)
[OK] hedge kamino Vanilla@7u3H #BXSz..zJPW: deposit $3291, borrow $585, LTV 22.2% of 90.0% liq (positions stale 157 h)
[OK] hedge kamino Vanilla@6WEG #Cz3p..NQqK: deposit $844, borrow $0, no debt (positions stale 157 h)
```

Four things in those lines are deliberate. A position whose basis is missing
reads `UNKNOWN` and gets no invented verdict. A position with no debt says so
instead of reporting 0% risk. Every Kamino line carries how long since Kamino
reindexed that wallet, so a three-day-old balance never reads as a current one;
the MarginFi line has no such timestamp to print.
And each row names the wallet label it came from: `own` is the operator's own
debt, the rest are watched addresses.

The stake side, same run:

```
Stake: 2 account(s), 1.099 SOL delegated, epoch 1112 at 74% (~12 h left).
[inactive] main: 1.008 SOL, validator deep.. ok, vote lag 0 slot(s), fee 100.0%
[active] spare: 1.099 SOL, validator APsE.. ok, vote lag 0 slot(s), fee 0.0%, last reward 0.002 SOL
```

An address outside the operator's allowlist is refused before any RPC call, and
the refusal names what is configured, and never echoes the request back:

```
wallet `9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM` is not in the configured
allowlist; known labels: main, hedge
```

## On-chain transactions behind these claims

Every row is a real transaction you can open. The program column matters more
than the signature: it shows the transaction actually touched the program the
plugin is written against.

| what it is | network | program invoked | transaction |
|---|---|---|---|
| The deposit that opened the position `lending-health` reads as `own` | mainnet | Kamino Lend `KLend2g3…` | [`5c8RyMPG…`](https://solscan.io/tx/5c8RyMPGtQjBT6ZWKrZ8AxqgCqM8MSKJ3dzAPaqUDaVeUhXAAWBAbrYXLHbPoRR3opdXADDfwgEzgkeFjxZCsJnm) |
| The borrow against it, 5 USDC | mainnet | Kamino Lend `KLend2g3…` | [`4w7dsihH…`](https://solscan.io/tx/4w7dsihHBa6BvjgBKFqCozktPEp72UhHTksyRPjsf7H2y6f1TBVday9hr719ABe7tjE6rDX9jQvXunKwEpZoYGz4) |
| The `delegate` that put the demo stake account into its `activating` state | devnet | Stake Program | [`3DwoSx4Y…`](https://explorer.solana.com/tx/3DwoSx4YSgfyamK96HixCC1agXQwWg6ru6G4BQHdTRY13cqwZh9rh9EQDS3BTdNkFNgTNVbxS1dadiByoPubS8qc?cluster=devnet) |
| The `deactivate` that produced the `deactivating` reading | devnet | Stake Program | [`2BrRUssX…`](https://explorer.solana.com/tx/2BrRUssXQ8byT6pKaFX6Vrgqh9fYPvbmUan1tRqHgag158DFfRdX5jxmDugzikCPANhb2zovtujVRuUqGzvGXWR4?cluster=devnet) |
| The mainnet `delegate` a golden test reproduces byte for byte | mainnet | Stake Program | [`5yaZiJMV…`](https://solscan.io/tx/5yaZiJMVnN5fM5K4rHQFrntaprKQJJbuLqiVGWh7Dkg1MqtswUno83BTozmzN8xAfLZTtFTZiwhTUZsmNoa5kVRA) |

All five confirm with `err: null`.

**Read the middle two rows precisely.** They were submitted with the Solana CLI
to build the devnet stand, and they are the events that gave `stake-monitor`
real lifecycle states to report, no fixtures. They are evidence for the
reader.

**Nothing the builder produced has ever been sent to a network, and that is the
design.** The plugin returns bytes with an empty signature slot; it holds no key
and cannot sign or submit. What was proven instead is that the Solana runtime
accepts those bytes: both a `deactivate` carrying a durable nonce and a
`delegate` on a fresh blockhash went through `simulateTransaction` on devnet
with `err: null`, at 10882 and 16956 compute units, with `AdvanceNonceAccount`
standing first in the durable case as the runtime requires. That transcript is
in [`SHOWCASE.md`](SHOWCASE.md); the last mile, an operator signing and sending,
stays with the operator.

## Safety model

Structural, written into the components, in four parts:

- **No custody.** No private key appears in config or code. The builder returns
  bytes; signing happens elsewhere, by a human.
- **Allowlists, not model input.** A hijacked model can narrow a query to fewer
  of the operator's own addresses. It cannot widen one to an attacker's address.
- **Fail-closed config.** An unknown or misspelled key is a hard error, not a
  silent default, so a typo like `max_amout` cannot quietly restore a wider
  limit.
- **Bounded output.** Tool arguments reject unknown fields, and both the report
  and the failure paths share one character cap. Text an outside party controls,
  such as a Kamino product tag or the `message` field of a JSON-RPC error, is
  treated as untrusted input to the model: it is presented as an explicit
  quotation, stripped of control characters, narrowed in character class where
  the field allows it, and capped, so it can carry a diagnostic without carrying
  an instruction.

Custody tiers, in the terms the ZeroClaw ladder uses: `lending-health` and
`stake-monitor` are **T0 Read**, and `stake-tx-build` is **T1 Build**. The most
sensitive value these plugins hold is an RPC endpoint URL, and none of them can
sign or submit. That statement covers the plugins only: the host config around
them holds a channel token and a model API key like any ZeroClaw install, and
those deserve the care the host documentation gives them.

Each plugin README carries a threat model and a live transcript of a
prompt-injection attempt being refused.

## Build and install

Requires a Rust toolchain with the `wasm32-wasip2` target. Per plugin:

```bash
git clone https://github.com/ZiBibro/solana-portfolio-sentinel
cd solana-portfolio-sentinel/plugins/lending-health
rustup target add wasm32-wasip2
cargo build --locked --target wasm32-wasip2 --release
cp target/wasm32-wasip2/release/lending_health.wasm .
zeroclaw plugin install .
```

The `.wasm` must sit beside `manifest.toml` when the installer runs, which is
why it is copied up from `target/`. Built artifacts are not committed here.

Running `plugin install` a second time is refused, never silently ignored:

```
Error: plugin 'lending-health' is already loaded
```

That matters when you rebuild. The refusal leaves the previously installed
`.wasm` in place, so a rebuilt component does not reach the host until you
remove the plugin first:

```bash
zeroclaw plugin remove lending-health && zeroclaw plugin install .
```

Configuration keys with worked examples, and the permissions a plugin requests are
documented in its own README under `plugins/`.

## Validation

Host tests run without a wasm toolchain and without network access:

| plugin | host tests |
|---|---|
| lending-health | 83 |
| stake-monitor | 47 |
| stake-tx-build | 81 |
| total | 211 |

CI runs `cargo fmt --check`, `cargo test --locked`, `cargo clippy --locked
--all-targets -- -D warnings` on both the host target and `wasm32-wasip2`, and a
locked release build for `wasm32-wasip2`, on Rust 1.96.1.

[`REPRODUCE.md`](REPRODUCE.md) walks an operator from a bare machine to a running
agent, including the host build, and every command in it was executed on the
machine that produced the demo.

Fixtures for `lending-health` and `stake-tx-build` are captures from live
endpoints, including a mainnet transaction and a MarginFi account. One MarginFi
fixture is synthetic and labelled as such in its doc comment, because no live
capture carried a written maintenance pair.

A note for operators behind TLS-intercepting antivirus or corporate proxies:
`wasmtime-wasi-http` trusts the bundled webpki roots only, so intercepted HTTPS
fails with `TlsProtocolError` for any HTTP-using plugin. Worth knowing before
debugging a plugin that works everywhere except one machine.

## Relationship to the official registry

The same code was proposed to
[`zeroclaw-labs/zeroclaw-plugins#63`](https://github.com/zeroclaw-labs/zeroclaw-plugins/pull/63)
on 18 July. The bounty listing was updated on 22 July asking contributors not to
open registry pull requests during the bounty and stating that registry merges
happen separately after judging, so on 1 August that PR was moved to draft with a
comment explaining the timing. It keeps its history and stays out of the
maintainers' review queue meanwhile.

That registry is not open intake by design, so this repository is where the
plugins live and get released regardless of how the review eventually lands.
This listing is not an endorsement by ZeroClaw Labs, who do not maintain or
audit anything here.

Built for [Build Solana-native plugins for ZeroClaw](https://superteam.fun/earn/listing/zeroclaw),
sponsored by Superteam Brasil.

## Licensing

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your
option.

`wit/` is copied verbatim from
[`zeroclaw-labs/zeroclaw`](https://github.com/zeroclaw-labs/zeroclaw)
(Apache-2.0) at the commit pinned in `wit/UPSTREAM_REF`, so the component builds
against the same interface definitions the host ships.
