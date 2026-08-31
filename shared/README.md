# The composition around the components

Three WebAssembly components do the reading and the byte encoding. This
directory holds everything that turns them into something an operator actually
runs: a schedule, the reading rules, and one procedure with a human gate.

Copy this directory into your ZeroClaw install root, so the paths become
`<install>/shared/skills/...` and `<install>/shared/sops/...`, then point the
config at them:

```toml
[skill_bundles.solana-sentinel]

# This key goes INTO the `[agents.<name>]` table your config already has. Pasting
# a second `[agents.<name>]` header is a duplicate key, and the host answers by
# resetting the whole config to defaults for that run with one warning line.
# REPRODUCE.md section 7.3 records what that looks like.
[agents.<your agent>]
skill_bundles = ["solana-sentinel"]

[sop]
sops_dir = "shared/sops"
step_scope_enforce = true
persist_runs = true
```

Omitting `directory` under the bundle is deliberate: it resolves to
`<install>/shared/skills/<bundle>/`, which is where these files now are.

**One trap, on the pinned host only.** There a relative `sops_dir` resolves
against the **process working directory**, not against `--config-dir`: start the
daemon from anywhere else and `zeroclaw sop list` reports `No SOPs found` and
suggests creating one, which reads exactly like a broken manifest. Either start
the daemon from the install root or write an absolute path. The skill bundle never
shared that behaviour. On a current host both resolve against the install root,
so `shared/sops` loads from any working directory.

## skills/solana-sentinel/morning-triage

The reading procedure. It exists because the same three mistakes were available
to any model looking at these reports: treating a position with no debt as a
missing reading, inventing a verdict for a position marked UNKNOWN from whatever
figures did parse, and shortening an address when relaying a pre-signing
summary. The last one matters most: an address truncated to its visible ends can
be matched by an attacker who grinds a keypair, which turns a verification step
into theatre.

It also tells the agent what to leave out. A clean morning is one line, and that
line is the product.

## skills/solana-sentinel/liquidation-price

The layering argument, in a file. `lending-health` reports a current LTV against
the liquidation LTV, and the gap between them is a percentage, which is the
honest unit for a component because it holds regardless of price. An operator
thinks in prices. Converting between the two is one GET
against Jupiter's keyless endpoint plus a multiplication, and that work has no
business inside a compiled WebAssembly component: it would buy nothing and cost
the operator a rebuild to change.

So it lives in a skill and uses the host's built-in `http_request` tool. The
component boundary stays for work that needs it, which here means decoding
MarginFi account bytes and encoding transactions by hand.

It also fails softly on purpose. If the price lookup dies, the skill says so and
reports the buffer percentage alone, because the percentage came from the chain
and the price is convenience. A convenience layer must never take down the
answer underneath it.

## sops/stake-deactivation-review

Deactivating a stake is the one operation here that changes state, and it is the
one an operator reaches for under pressure, when a loan needs collateral and the
stake is the only liquidity in reach. That combination earns a procedure.

Five steps: read the stake, read the debt side, **stop**, build, hand off. The
procedure declares `execution_mode = "step_by_step"`, so the host raises an
approval gate before every one of those five, the build included, and each pause
is recorded in the audit trail under the run id.

Step three carries `kind: checkpoint` and `requires_confirmation: true` on top of
that, which is what makes its gate independent of the mode: the engine honours
`requires_confirmation` before it consults the execution mode at all, so relaxing
the mode later leaves this one pause standing. Its position is the point. An
approval attached to the build step asks the operator to approve a tool call
whose arguments are already chosen; a gate before it asks them to approve the
decision, with both readings on screen and nothing constructed yet.

Per-step tool scopes keep the reading steps away from the builder. With
`step_scope_enforce = true` those scopes are enforced filters rather than hints.

Validate before relying on it:

```bash
zeroclaw sop validate stake-deactivation-review
zeroclaw sop graph stake-deactivation-review
```

The graph prints five steps in order with `manual` feeding step one.

**Starting a run: use the gateway, not the chat.** The trigger is `manual`, and
on the pinned host asking the agent in the channel did not start a run in three
consecutive attempts: `sop_execute` appears zero times in the trace for all
three, and naming the procedure by id gets the message killed by the reply-intent
precheck first. What worked is the host's HTTP gateway, `POST /pair` followed by
`POST /api/sops/stake-deactivation-review/run`.

Then expect five gates, not one. The run parks before step one with nothing read
yet, and each gate is cleared with `zeroclaw sop approve <run-id>` on the CLI or
`POST /admin/sop/approve`, never from the messenger. The loop is `sop pending` to
see the waiting run, `sop approve <run-id>`, repeat until `sop pending` reports
nothing waiting. A run that looks stalled immediately after the POST is usually a
run waiting on its first gate.
[`REPRODUCE.md`](../REPRODUCE.md) section 7.4 carries the exact calls.

The daily brief is a top-level `[cron.*]` job rather than a cron-triggered SOP.
That split is deliberate and is documented with the full config in
[`REPRODUCE.md`](../REPRODUCE.md).
