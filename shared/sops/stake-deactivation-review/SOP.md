# Stake deactivation review

Undelegating a stake account is a decision with a cost: the lamports stop
earning the moment the transaction lands, and they stay idle through the
cooldown before they can be moved. It is also the operation an operator reaches
for under pressure, when a loan needs collateral and the stake is the only
liquidity in reach. That combination is why it gets a procedure instead of a
single tool call.

The procedure gathers the two readings the decision rests on, stops for the
operator, and only then builds anything. Nothing here signs or submits.

## Steps

1. **Read the stake** — Call `stake_monitor` and report the account named by the
   operator: its delegation state, the validator's voting health and lag, epoch
   progress, and last epoch's reward. State plainly whether the account is
   currently earning anything.
   - tools: stake_monitor
   - allow-tools: stake_monitor

2. **Read the debt side** — Call `lending_health` for the watched wallets. Freed
   stake is often meant for a loan, so the decision changes with what the loan
   looks like now. If every position is comfortable, say so: it may mean the
   deactivation can wait for the epoch boundary instead of happening today.
   - tools: lending_health
   - allow-tools: lending_health

3. **Present the case and stop** — Put the two readings side by side and state
   the tradeoff in the operator's terms: what stops earning, how long the
   cooldown runs, what the freed lamports are for. Name the alternative of doing
   nothing. Do not recommend. Then wait.
   - kind: checkpoint
   - requires_confirmation: true

4. **Build the unsigned transaction** — Call `stake_tx_build` with action
   `deactivate` for the approved account only. Relay the summary exactly as the
   tool returns it, with every address in full and the signer count as stated.
   Never shorten an address.
   - tools: stake_tx_build
   - allow-tools: stake_tx_build

5. **Hand it off** — Tell the operator the transaction is unsigned and that
   signing happens in their own wallet, outside this system. If the summary
   named a durable nonce, say the transaction survives a slow approval; if it
   did not, name the blockhash window it is living inside.

## Why the checkpoint sits where it does

Step 3 is a checkpoint rather than a confirmation on step 4, and the difference
matters. An approval attached to the build step asks the operator to approve a
tool call, at a moment when the arguments are already chosen. A checkpoint
before it asks them to approve the decision, while both readings are on screen
and nothing has been constructed. The run pauses there until a human advances
it, and the pause is recorded in the audit trail under the run id.

The step scopes are declared per step, so the readers cannot reach the builder
and the builder runs only after the pause. With `step_scope_enforce = true` in
the `[sop]` config these become enforced filters rather than hints.
