# solana-portfolio-sentinel

[![CI](https://github.com/ZiBibro/solana-portfolio-sentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/ZiBibro/solana-portfolio-sentinel/actions/workflows/ci.yml)

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

## The readers

### lending-health

Reads Kamino positions from the public Kamino REST API and decodes MarginFi
positions from on-chain account state via `getProgramAccounts`, at the byte
offsets where the program keeps its maintenance-weighted health cache. Each
position is classified OK/WARN/CRITICAL against operator-set LTV thresholds,
and each line names the obligation it came from.

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
discriminants, account metas) with no `solana-sdk` dependency, since that crate
does not build for `wasm32-wasip2` inside a WIT component. The instruction bytes
are locked by a golden test that reproduces a live mainnet delegate transaction
byte for byte.

Before building anything it verifies the endpoint's genesis hash against the
operator's pinned cluster and refuses on mismatch, so an honest endpoint pointed
at the wrong network cannot produce a transaction the operator believes is for
mainnet. Delegation stays disabled until the operator opts in by listing vote
accounts. With an optional durable-nonce pair configured, the transaction opens
with `AdvanceNonceAccount` and survives a slow approval queue; without one, the
summary states the roughly 60 to 90 second blockhash window.

## Safety model

Structural rather than prompt-based, in four parts:

- **No custody.** No private key appears in config or code. The builder returns
  bytes; signing happens elsewhere, by a human.
- **Allowlists, not model input.** A hijacked model can narrow a query to fewer
  of the operator's own addresses. It cannot widen one to an attacker's address.
- **Fail-closed config.** An unknown or misspelled key is a hard error, not a
  silent default, so a typo like `max_amout` cannot quietly restore a wider
  limit.
- **Bounded output.** Tool arguments reject unknown fields, upstream error
  bodies are never echoed into the agent context, and both the report and the
  failure paths share one character cap.

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

Configuration keys, worked examples, and the permissions a plugin requests are
documented in its own README under `plugins/`.

## Validation

Host tests run without a wasm toolchain and without network access:

| plugin | host tests |
|---|---|
| lending-health | 59 |
| stake-monitor | 35 |
| stake-tx-build | 36 |

CI runs `cargo fmt --check`, `cargo test --locked`, `cargo clippy --locked
--all-targets -- -D warnings` on both the host target and `wasm32-wasip2`, and a
locked release build for `wasm32-wasip2`, on Rust 1.96.1.

Fixtures for `lending-health` and `stake-tx-build` are captures from live
endpoints, including a mainnet transaction and a MarginFi account. One MarginFi
fixture is synthetic and labelled as such in its doc comment, because no live
capture carried a written maintenance pair.

A note for operators behind TLS-intercepting antivirus or corporate proxies:
`wasmtime-wasi-http` trusts the bundled webpki roots only, so intercepted HTTPS
fails with `TlsProtocolError` for any HTTP-using plugin. Worth knowing before
debugging a plugin that works everywhere except one machine.

## Relationship to the official registry

The same code is proposed to
[`zeroclaw-labs/zeroclaw-plugins#63`](https://github.com/zeroclaw-labs/zeroclaw-plugins/pull/63),
which is open and stays open. That registry is not open intake by design, so
this repository is where the plugins live and get released regardless of how
that review lands. This listing is not an endorsement by ZeroClaw Labs, who do
not maintain or audit anything here.

Built for [Build Solana-native plugins for ZeroClaw](https://superteam.fun/earn/listing/zeroclaw),
sponsored by Superteam Brasil.

## Licensing

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your
option.

`wit/` is copied verbatim from
[`zeroclaw-labs/zeroclaw`](https://github.com/zeroclaw-labs/zeroclaw)
(Apache-2.0) at the commit pinned in `wit/UPSTREAM_REF`, so the component builds
against the same interface definitions the host ships.
