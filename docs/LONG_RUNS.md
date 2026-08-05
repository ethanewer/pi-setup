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

The decisive detail: **Pi already compacts and then keeps going by itself.** When
`_checkCompaction` returns true, `_handlePostAgentRun` returns true too and
`_runAgentPrompt`'s loop calls `agent.continue()` (`agent-session.js:744-750, 776`); on
overflow it compacts and retries the interrupted step (`:1533-1556`); and its native
summarization is handed a retry policy (`:1662`, 3 retries / 2s backoff). The extension
replaced a zero-failure-link mechanism with a five-link one — and was strictly *less*
resilient than the Pi behaviour it displaced.

(Earlier revisions of this paragraph said Pi compacts "mid-turn". It does not — the check
runs only after an agent run returns, which is why context can overshoot the window inside
one long run. See [Configuration for long runs](#configuration-for-long-runs). What matters
here is unchanged: Pi resumes on its own after compacting, so no extension needs to
orchestrate a resume.)

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
{ "compaction": { "reserveTokens": 68000 } }
```

Compaction fires when context exceeds `contextWindow - reserveTokens`. There are hazards
at both ends, and the low end is the one that actually bit.

> **`reserveTokens` must cover a whole agent run, not a whole reply.** Pi evaluates the
> threshold only *after* a run finishes. `_checkCompaction` is reached from
> `_handlePostAgentRun`, which runs after `await this.agent.prompt(...)` returns
> (`agent-session.js:744-750`). An agentic run can be hundreds of entries long, so a run
> can cross the threshold early and keep going for the rest of it. Pi's default of 16384
> quietly assumes the check happens often.
>
> Measured on session `019fb8da` (2026-07-31, `gpt-5.6-sol`, 272000-token window,
> `reserveTokens` 16384): the 255616 threshold was crossed at 265232 tokens, and the turn
> then ran **64 more model calls over 17 minutes**, peaking at **290536 — 18536 tokens past
> the window**. It survived only because the provider tolerated the overflow. A slightly
> longer turn would have hit a hard context error mid-run, which is the exact failure this
> document exists to prevent.
>
> Session `019fcaa8` (2026-08-04) then showed 45000 was still too small, and showed it in
> the most useful way: the run **started at 214665**, just under that setting's 227000
> threshold, so Pi correctly declined to compact first. The run then grew **53324 tokens
> across 49 calls** — more than the 45000 of window it had been left — and hit the ceiling
> at 267989 with about 4000 tokens spare. **68000 would have compacted before that run ever
> started.** The reserve must exceed the growth of one whole run, and 53324 is the largest
> single-run growth measured so far.

> **A larger reserve is slack, not a bound. It cannot stop an overrun.** Because the check
> only happens between runs, a long enough run passes any threshold you set. Observed on
> `mk` on 2026-08-03 *with* `reserveTokens: 45000` already applied: a single run reached
> **120.5% of the 272000-token window, about 328000 tokens**, worse than the 290536 that
> motivated the setting. The reserve makes compaction trip sooner at every run boundary,
> so a session spends less time near the ceiling — that is worth having, and it is all it
> buys.
>
> **Pi cannot be made to compact within a run, but the request can be shrunk before it is
> sent.** `ctx.compact()` is no use: it delegates to `AgentSession.compact()`, which opens
> with `this._disconnectFromAgent(); await this.abort();`, so calling it from `turn_end`
> aborts the very run it was protecting. Pi also exposes no `maxTurns` or `maxSteps`, and
> `compaction` settings are only `enabled`, `reserveTokens`, and `keepRecentTokens`.
>
> Earlier revisions of this document concluded from that "there is no code fix available to
> an extension". That was wrong, and the mistake is worth recording: the survey covered the
> compaction API and the turn hooks, and never asked what shapes the *request*. The `context`
> hook — "fired before each LLM call, can modify messages" — returns the array the provider
> actually receives (`agent-loop.js:181`). That is the same position in the loop where Codex
> makes its own mid-turn compaction decision, and it is reachable from an extension.
>
> [`pi-codex-compaction`](../forks/pi-codex-compaction/README.md) uses it. See
> [Folding context inside a run](#folding-context-inside-a-run) below for what that does and
> does not change. Two things stay true regardless: within-run *history* still grows, because
> that fold shapes one request and never rewrites the session; and a run that never yields
> still relies on a mechanism that can fail.
>
> So what bounds growth for certain is still **ending the run**. A turn that finishes lets
> Pi's own check run, and compaction happens immediately — the yield-and-be-woken pattern the
> monitor exists for: report progress, end the turn, let a watcher steer you back when the job
> moves.
>
## When the model is truncated, Pi compacts and then abandons the run

This is a separate failure, seen three times on 2026-08-04, and it is the one that looks
most like "the agent just stopped".

When context leaves no room to generate, the provider truncates the reply. Every occurrence
had the same shape: `stopReason: "length"`, `rawStopReason: "incomplete"`, **one empty
thinking block, `output: 16`**, and `input + cacheRead` around 267,700 of a 272,000 window.
The work was unfinished — there was no tool call and no answer.

Pi has a case for exactly this. `isContextOverflow` case 3 covers "server truncates
oversized input, leaving no room for output" — but it requires **both**
`usage.output === 0` and `input + cacheRead >= contextWindow * 0.99`. These messages carried
16 reasoning tokens rather than 0, and sat at 98.4%, just under the 269,280 floor. Both
conditions missed, so a truncation was classified as a routine threshold compaction, which
ends with:

```js
if (willRetry) { ...; return true; }        // resume
return this.agent.hasQueuedMessages();       // false -> the run is over
```

The compaction succeeds and the run silently ends, with no error and nothing in the
transcript after it.

**That last line is also the fix, and production proved it.** `session_compact` is emitted
and awaited *before* that return, so anything queued during the hook makes
`hasQueuedMessages()` true and Pi calls `agent.continue()`. In session `019fcd7f` the same
truncation happened twice: at 16:56:38 a monitor watcher event landed **28 ms** after the
compaction and the run carried on for another 600 entries; at 18:36:39 nothing was queued
and the run sat dead until a human typed **64 minutes** later. The monitor had accidentally
rescued the first one.

### The fix, and what it does and does not guarantee

Truncation is only one of the ways `_runAutoCompaction` returns false and ends a run. The
others are a compaction that threw, nothing to compact, an aborted compaction, and overflow
recovery that has already spent its single `_overflowRecoveryAttempted` retry. **Three of
those never emit `session_compact` at all**, so a hook there cannot see them.

`pi-context-handoff` therefore resumes at two points:

1. **`session_compact`** — the cheap path, used when a truncation was compacted. Queuing
   there makes `hasQueuedMessages()` true and Pi calls `agent.continue()`, carrying on
   inside the same run.
2. **`agent_settled`** — the backstop. Pi documents it as "will not continue running
   automatically", and it is emitted from `_runAgentPrompt`'s `finally`, so it fires on
   every stopping path. If the run ended unfinished and nothing already rescued it, a
   resume is injected with `triggerTurn`, which starts a new turn.

"Unfinished" is `stopReason` of `length` or `error`. **`stop` and `aborted` are never
resumed** — the first is the model deliberately finishing, the second is you cancelling, and
resuming either would talk over you. That gating is what stops `agent_settled`, which fires
after *every* run, from making the agent chatter.

Verified end to end in tmux rather than only in unit tests: with the
`PI_CONTEXT_HANDOFF_FORCE_RESUME=1` seam the transcript shows the first turn, the injected
`[context-handoff-resume]` message, and then a genuinely new model turn. Normal runs were
checked too and inject nothing.

**The bounds, stated plainly.** It gives up after three consecutive unfinished resumes and
says why, because an unrecoverable context is better ended than looped on. It cannot help if
the `pi` process itself dies, and it does not stop context from growing inside a run — for
that see [Folding context inside a run](#folding-context-inside-a-run). What it does guarantee
is that Pi deciding to stop a run at a compaction boundary no longer ends it silently.

See [`forks/pi-context-handoff/extensions/context-handoff/resume.ts`](../forks/pi-context-handoff/extensions/context-handoff/resume.ts).

> Pi is not defenceless if the provider does reject the request: `_checkCompaction` case 1
> detects a context-overflow response, compacts, and retries once
> (`_overflowRecoveryAttempted`). So an overrun is expensive and outside the documented
> envelope rather than immediately fatal.

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

## Folding context inside a run

Everything above treats within-run growth as unbounded, because Pi checks its threshold only
between runs. Codex does not have that gap: `codex-rs/core/src/session/turn.rs:493` checks
after every sampling request, compacts inline, and `continue`s the loop, so compaction is a
step in the loop rather than a verdict on whether the loop survives.

[`pi-codex-compaction`](../forks/pi-codex-compaction/README.md) puts that decision at the
same point in Pi's loop, using the `context` hook. Above 90% of the context window — Codex's
own trigger, `(context_window * 9) / 10`, and configurable only downward — the old part of the
history is replaced, *for that request only*, with a summary of it, the user's instructions
from it verbatim, and the recent tail untouched.

**What it changes.** A single long run stops walking off the end of the window. Verified with
the `PI_CODEX_COMPACTION_FORCE_TRIGGER_TOKENS` seam, since a 245000-token conversation cannot
be produced on demand: across four tool calls in one run the provider's own usage records went
6352 → 8186 → 10822 → **9442** → **9470** tokens, falling at the first fold and then staying
flat while two more tool results arrived. Both folds discarded the original user message and
both rescued it verbatim, and the run still answered the literal string it had been asked for.
The audit trail is in the session: one `codex-compaction-fold` custom entry per fold, which
Pi persists and never shows the model.

**What it does not change.** Four things, all of them load-bearing:

1. **History still grows.** The `context` hook shapes one request; it does not rewrite the
   session. The transcript, and Pi's own footer percentage, keep counting everything. Only
   what is *sent* shrinks. `/codex-compaction` shows the real figure.
2. **It is not a replacement for Pi's compaction.** Pi's between-runs compaction is the one
   that genuinely shrinks history, and `reserveTokens` still governs it. When it fires, the
   fold's fingerprints stop matching and the fold is discarded in favour of it.
3. **It cannot make things worse, and that is the trade.** Codex ends the turn when its
   compaction fails (`turn.rs:504`). Every failure path here — no credential, empty summary,
   provider outage, aborted signal, nothing left to fold, three failures in a row — returns
   the messages Pi handed in, which is exactly the behaviour of not installing it. The price
   is that a fold is never guaranteed to happen.
4. **`reserveTokens` stays at 68000 for now.** Codex can afford a 90% trigger *because* it
   checks after every sampling request; the 68000 here exists because Pi cannot. It is
   tempting to lower it now toward Codex's ~27200, and that would be premature: the fold has
   been demonstrated with a forced trigger, not yet by carrying a real run past 245000 tokens.
   Revisit once a production run has done that.

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
