# pi-context-handoff

Makes compaction survivable for long autonomous runs, from three angles:

1. **Handoff briefs** — shapes Pi's native between-runs compaction into a `## Goal`-style
   handoff (objective, constraints, done-vs-remaining + next action, ruled-out
   approaches), via Pi's own `compact()`.
2. **Mid-run fold** — the Codex-style fold that shapes the request inside a run before
   every LLM call, closing the gap where Pi's threshold check only runs between runs.
   Ported from the former `pi-codex-compaction` package, merged here when the two
   companion packages were unified into one.
3. **Resume** — resumes a run Pi ended on a truncated reply (`stopReason "length"`) or
   `error`, a case Pi's own overflow test misses. Never resumes `stop`/`aborted`; gives up
   after three consecutive unfinished resumes.

First-party extension, not a fork. It replaces `pi-continue`, which stopped long runs
(see [`../../docs/LONG_RUNS.md`](../../docs/LONG_RUNS.md)).

## The one design constraint

This extension **must not be able to stop a run**. It never calls `ctx.abort()` and never
returns `{ cancel: true }`. Every failure path in all three halves degrades to stock Pi
behavior:

- Handoff falls back to Pi's native compaction with Pi's own retries. The worst outcome is
  a less useful summary.
- The fold sends the original messages on any failure — byte-for-byte the behaviour of not
  installing this package.
- The resume sends one queued nudge, and only where Pi has already decided to end the
  run. Cap on consecutive resumes is 3, after which it says why and stops.

## Handoff briefs (between runs)

Hooks `session_before_compact`, calls Pi's own `compact()` with focus instructions plus a
retry policy, and returns the result as the compaction. The value is in the instructions
([`instructions.ts`](extensions/context-handoff/instructions.ts)), which tell the
summarizer to preserve the objective, constraints, done-versus-remaining with a concrete
next action, durable specifics, and ruled-out approaches — and to state plainly that the
task is unfinished rather than reading as a conclusion.

Pi already resumes on its own when `_checkCompaction` returns true — the run continues
through `agent.continue()`. This hook only shapes *what the summary says*, never *when*.

## Mid-run fold (Codex-style)

Pi's threshold check fires only after `agent.prompt()` returns or before a new prompt —
everything inside one run accumulates unchecked, which is how a run reaches past its
context window and dies on a truncated reply. Pi's `context` hook ("fired before each LLM
call, can modify messages") is the same point in the loop that Codex compacts at, so the
fold lives there.

The fold summarizes the old prefix, pins user instructions verbatim under a 20k-token
budget, and keeps a 20k-token recent tail. It is **non-destructive**: session history is
never rewritten, the fold is recomputed and re-applied per call, and it is discarded when
Pi's own compaction fires (native supersedes it, by design). Guards stand down after two
folds without getting under the trigger, or after three consecutive summarization
failures. `fold.ts` holds every decision and is pure; `fold-hook.ts` is the plumbing.

## Resuming a run Pi abandoned

When context leaves no room to generate, the reply is truncated (`stopReason "length"`),
and Pi's overflow test misses the shape (it requires `usage.output === 0` and ≥99% of the
window). Pi then ends the run silently. `session_compact` fires before the end check, so
a message queued there makes Pi continue the same run — observed in production: one such
resume kept a run going for another 600 entries while an identical compaction sat dead
for 64 minutes. `agent_settled` is the backstop for end-of-run paths that never emit
`session_compact` (thrown compaction, nothing to compact, aborted compaction, spent
overflow retry). Only `length`/`error` count as unfinished; `stop` and `aborted` are
never resumed. Resume logic is in
[`extensions/context-handoff/resume.ts`](extensions/context-handoff/resume.ts).

## Configuration

One file, read relative to `PI_CODING_AGENT_DIR`:

- `pi`: `~/.pi/agent/extensions/pi-context-handoff.json`
- `p`: `~/.pi/agent-p/extensions/pi-context-handoff.json`

```json
{
  "enabled": true,
  "focus": "",
  "retry": { "enabled": true, "maxRetries": 3, "baseDelayMs": 2000 },
  "notifyOnFallback": true,
  "fold": {
    "enabled": true,
    "focus": "",
    "triggerPercent": 0.9,
    "keepRecentTokens": 20000,
    "pinUserTokens": 20000,
    "minSavingTokens": 4000,
    "toolOverheadTokens": 4000,
    "summaryReserveTokens": 16384,
    "maxFailures": 3,
    "maxFoldsWithoutProgress": 2,
    "maxTrimAttempts": 5,
    "notify": true,
    "retry": { "enabled": true, "maxRetries": 3, "baseDelayMs": 2000 }
  }
}
```

Top-level keys configure the handoff half; the optional `fold` object configures the
mid-run fold. A legacy `~/.pi/agent/extensions/pi-codex-compaction.json` from the
pre-merge standalone package is still honored for fold settings when `fold` is absent.

Any `customInstructions` Pi was already going to use (a `/compact` argument, or another
extension's contribution) are preserved and appended, not overridden.

## When compaction happens

The fold decides its own timing (≥90% of the window, clamped so config can only fold
earlier); the handoff half does not decide — Pi does. Tune Pi's own settings:

```json
{ "compaction": { "enabled": true, "reserveTokens": 68000, "keepRecentTokens": 20000 } }
```

Keep `reserveTokens` well below the model's context window — setting it near the window
produces a summarization request that can stall.

## Verification

`PI_CODEX_COMPACTION_FORCE_TRIGGER_TOKENS=<n>` forces the fold trigger to an absolute
token count (the only way to exercise a real fold end to end), and
`PI_CONTEXT_HANDOFF_FORCE_RESUME=1` forces the resume backstop once. `/codex-compaction`
(and its alias `/context-handoff`) shows live fold state.

To typecheck the extension (Pi loads the `.ts` source; this is optional):

```sh
mkdir -p node_modules/@earendil-works
for p in pi-coding-agent pi-ai pi-tui pi-agent-core; do
  ln -sfn ~/.bun/install/global/node_modules/@earendil-works/$p node_modules/@earendil-works/$p
done
npm i -D typescript@5 @types/node
./node_modules/.bin/tsc --noEmit -p tsconfig.json
```

(`node_modules` here is for that check only; it is not a runtime dependency.)
