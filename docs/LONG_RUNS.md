# Running long without stopping

This setup is tuned for autonomous runs that continue across compaction boundaries,
provider hiccups, and large fan-outs. This document records the three failure modes that
used to stop a run, what fixed each, and what can still stop one.

## The three failures, and their causes

### 1 and 2 were the same bug

"Agent stopped due to OpenAI API errors" and "agent stopped after compaction" were one
defect in `pi-continue`, not two:

1. Crossing the context threshold made the extension **abort the running turn**
   (`runtime.ts:360`) — deliberately, because it intended to compact and then re-inject a
   resume prompt.
2. It then called its own summarizer with **one request and no retry**
   (`model.ts:97-131`).
3. Any transient fault — a 429, a 500, a dropped connection — failed synthesis, so the
   compaction carried no `continuationEventId`, the proof check bailed, and
   **`dispatchVerifiedContinuationResume` never ran**.
4. Net effect: turn aborted, compaction saved, no resume dispatched. The agent sat idle
   waiting for a human. A `guardFailureKey` latch then aborted the next attempt at the
   same checkpoint too.

The decisive detail: **Pi already compacts mid-turn and keeps going.**
`_checkCompaction` returns true and the agent loop continues (`agent-session.js:776`), on
overflow it compacts and retries the interrupted step (`:1533-1556`), and its native
summarization is handed a retry policy (`:1662`, 3 retries / 2s backoff). The extension
replaced a zero-failure-link mechanism with a five-link one — and was strictly *less*
resilient than the Pi behaviour it displaced.

Two caps made it worse, and they were mine: `maxChainedContinuations: 10` and
`maxChainedSynthesisCostUsd: 5`, added during the security audit. The counter only reset
on **new operator input**, so a fully autonomous run accumulated toward a hard stop that
upstream did not have.

**Fix:** `pi-continue` is retired, replaced by
[`pi-context-handoff`](../forks/pi-context-handoff/README.md). It steers Pi's own
compaction instead of replacing it: hook `session_before_compact`, call Pi's `compact()`
with focus instructions plus a retry policy, return the result. It never aborts a turn,
never injects a resume prompt, and every failure path returns `undefined` — which means
"Pi, do your own compaction," exactly as if it were not installed.

### 3: too many monitors, no way to close them

Already solved by `pi-process-monitor-safe`: a 16-watcher cap enforced in `launch()`,
plus `monitor_kill` and `monitor_kill_all`. Heartbeats are off by default, aggregated into
one message by a single 30s scheduler, and capped at 8 KB / 64 lines, so watchers cannot
flood the context either.

## Also fixed: workflow agents died on transient faults

`defaultAgentRetries` was **0**, so one dropped connection permanently degraded a
subagent's result to `null`. This is not hypothetical — it happened during this work:

```
[verify2:dynamic-workflows] failed: API Error: Connection closed mid-response.
```

A generic provider error is already classified `recoverable: true`
(`errors.ts:259-262`); it simply never retried. Now:

- `DEFAULT_AGENT_RETRIES = 2` (3 attempts total).
- Exponential backoff between attempts, 2s base, 30s ceiling — an immediate retry into a
  transient upstream fault usually just reproduces it.
- Abort during a backoff is still honoured, so cancelling stays responsive.
- `DEFAULT_AGENT_TIMEOUT_MS` raised from 15 to 60 minutes. A timeout degrades that agent
  to `null`, so too low a value silently loses legitimate long work.

Genuine quota and rate limits are handled differently and correctly: they throw
`PROVIDER_USAGE_LIMIT`, which **checkpoints the run as paused** for the usage-limit
scheduler to auto-resume, rather than burning retries against the same wall.

## Side questions do not interrupt the run

`/btw` ([`pi-btw-side`](../forks/pi-btw-side/README.md)) answers in a separate
`AgentSession` with its own in-memory session manager, displayed in an overlay. It cannot
abort the main turn, cannot add anything to the main thread's context, and its failures
surface inside its own view rather than as an exception in Pi's event loop. Asking
mid-turn is supported and tested: the main turn keeps streaming behind the view and
finishes normally, and the history snapshot the fork inherits is trimmed back to the last
resolved tool call so a half-finished turn cannot produce an invalid request.

It also cannot quietly consume the context it was meant to protect. The side conversation
is discarded when the view closes, and even with `record: true` what it leaves behind is a
custom entry, which Pi never sends to a model.

## Configuration for long runs

Compaction is Pi's job, not an extension's. Tune it in `~/.pi/agent/settings.json`:

```json
{ "compaction": { "enabled": true, "reserveTokens": 16384, "keepRecentTokens": 20000 } }
```

Compaction fires when context exceeds `contextWindow - reserveTokens`. Pi's defaults are
sensible; the only real hazard is setting `reserveTokens` too high.

> **Do not set `reserveTokens` near the context window.** It leaves almost no usable
> context and produces a summarization request that stalls with no output and no error —
> the process simply sits idle. Found the hard way while testing this. `bin/pi-setup-doctor`
> now checks for it, and flags `compaction.enabled: false` as well, since a long run with
> compaction off will hit the context limit and stop.

Retries are on by default and unset in this setup (`retry.enabled` defaults true,
`maxRetries` 3, `baseDelayMs` 2000). Leave them on.

## What can still stop a run

Being honest about the remaining edges:

- **A confirmation prompt with no one to answer it.** The security hardening gates some
  capabilities behind an explicit opt-in (see [`FORKS.md`](FORKS.md)). In an unattended
  run these fail closed with an actionable message rather than hanging, so the agent can
  route around them — but the gated action itself will not happen. If a long run needs
  one, set the opt-in before starting.
- **A genuine, sustained provider outage.** Retries and the usage-limit scheduler cover
  minutes, not hours.
- **Context that cannot be compacted.** If the recent-turn window alone exceeds the
  threshold, there is nothing left to summarize. Lower `keepRecentTokens` if you hit it.
- **A missing helper binary on a cold install.** Pi fetches `fd` on first tool use; if
  that fetch cannot complete, the first tool call blocks. `~/.pi/agent/bin` is populated
  after any successful interactive run, so do one before relying on unattended runs on a
  fresh machine.

## How this was verified

- Pi's mid-turn compact-and-continue was confirmed by reading the agent loop
  (`agent-session.js:776`, `:1533-1556`, `:1662`) and by a live multi-tool run captured
  as a JSON event stream, which showed successive `turn_start` → tool call →
  `tool_execution_end` → `turn_end` cycles continuing normally.
- `pi-context-handoff`'s pure logic is unit-tested: instruction assembly (including that
  a malformed config degrades to defaults with retries still enabled, and that inherited
  `customInstructions` are preserved rather than overridden).
- End-to-end, a **real threshold compaction** was driven in an isolated agent dir (40k
  window, `reserveTokens` 6000, seven ~6k-token files). Instrumented, it showed the
  extension loading, the hook firing with `reason=threshold`, and a compaction being
  returned; `compaction_end` then recorded a summary **byte-identical in length (825) to
  what the extension returned**, proving Pi used it verbatim rather than falling back. The
  summary carried the objective, progress so far, and the concrete next action.
- Two caveats worth recording. `/compact` in `-p` mode produces no compaction entry, so it
  is not a usable trigger for testing; use a real threshold. And a "begin the summary with
  <token>" instruction cannot be verified literally, because Pi's `compact()` prepends its
  own wrapper (`Turn Context (split turn)`) ahead of the model's text — the instructions
  shape the body, not position zero.

Three methodological notes worth keeping:

- `pi -p` buffers all output until the run finishes, and an idle process at 0% CPU is
  normally just waiting on the provider. Several apparent "hangs" during this work were
  slow runs, not stalls — the same task completed on a later attempt. Use `--mode json`
  to see progress as it happens.
- Pi fetches a helper binary (`fd`) on first tool use. In an agent dir with no `bin/`,
  the first tool call blocks on that fetch, which does look exactly like a hang.
- `pi -p` is single-shot: it answers the prompt and exits. In the compaction test the
  model ended its turn after four of seven files and Pi compacted afterwards, which is
  print-mode behaviour, not the extension's. Long autonomous runs belong in an
  interactive session or a driving loop.
