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

- `DEFAULT_AGENT_RETRIES = 2` (3 attempts total). This did not actually take effect until
  2026-07-30: the manager resolved an unset retry count with `?? 0`, and the extension
  passes an unset one unless a settings file exists, so every real run got a single
  attempt while this document claimed otherwise. Found by the extension audit; the
  constant is now reachable and an explicit `0` is still honoured.
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

Compaction is Pi's job, not an extension's. `install.sh` writes it into
`~/.pi/agent/settings.json` and `~/.pi/agent-p/settings.json`:

```json
{ "compaction": { "reserveTokens": 45000 } }
```

Compaction fires when context exceeds `contextWindow - reserveTokens`. There are hazards
at both ends, and the low end is the one that actually bit.

> **`reserveTokens` must cover a whole turn, not a whole reply.** Pi evaluates the
> threshold *between turns*. An agentic turn can be hundreds of entries long, so a run can
> cross the threshold early in a turn and keep going for the rest of it. Pi's default of
> 16384 quietly assumes the check happens often.
>
> Measured on session `019fb8da` (2026-07-31, `gpt-5.6-sol`, 272000-token window,
> `reserveTokens` 16384): the 255616 threshold was crossed at 265232 tokens, and the turn
> then ran **64 more model calls over 17 minutes**, peaking at **290536 — 18536 tokens past
> the window**. It survived only because the provider tolerated the overflow. A slightly
> longer turn would have hit a hard context error mid-run, which is the exact failure this
> document exists to prevent.
>
> 45000 puts compaction at 227000 on that window, leaving room for the ~25000 tokens that
> turn added after crossing.

> **Do not set `reserveTokens` near the context window either.** It leaves almost no usable
> context and produces a summarization request that stalls with no output and no error —
> the process simply sits idle. Found the hard way while testing this.

[`config/compaction.json`](../config/compaction.json) holds the policy and the measurement
behind it. `install.sh` and `bin/pi-setup-doctor` both read that one file, so the number
cannot drift between what gets installed and what gets checked. The reserve is scaled down
on small-context models (at most a quarter of the window, never below Pi's 16384) so it
never collides with the upper bound. An existing larger value is left alone — install only
ever raises it. The doctor also flags `compaction.enabled: false`, since a long run with
compaction off will hit the context limit and stop.

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
- **A browser session idling out mid-run.** Since `agent-browser` 0.33.1 the daemon exits
  after an hour with no commands, so a long run that leaves the browser alone for that long
  comes back to a fresh one: open tabs and any state without a restore key are gone. It
  fails visibly rather than silently — the next command starts a new daemon — but work
  staged in a tab is lost. Set `--idle-timeout 0`, or give the session a restore key, if a
  run needs the browser to survive long gaps.
- **A missing helper binary on a cold install.** Pi fetches `fd` on first tool use; if
  that fetch cannot complete, the first tool call blocks. `~/.pi/agent/bin` is populated
  after any successful interactive run, so do one before relying on unattended runs on a
  fresh machine.

## How this was verified

- Pi's mid-turn compact-and-continue was confirmed by reading the agent loop
  (`agent-session.js:776`, `:1533-1556`, `:1662`) and by a live multi-tool run captured
  as a JSON event stream, which showed successive `turn_start` → tool call →
  `tool_execution_end` → `turn_end` cycles continuing normally.
- `pi-context-handoff`'s file-list carry-forward is unit-tested (`tests/carry-files.test.ts`):
  format parity with Pi's own `formatFileOperations`, the merge, stripping the old block,
  and carrying the previous compaction's lists into a new summary. Its instruction assembly
  and config parsing are not yet covered by tests.
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
