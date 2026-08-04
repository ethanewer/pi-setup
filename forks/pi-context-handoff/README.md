# pi-context-handoff

Makes Pi's compaction summary a usable handoff brief for a long autonomous run — and
nothing else.

First-party extension, not a fork. It replaces `pi-continue`, which stopped long runs
(see [`../../docs/LONG_RUNS.md`](../../docs/LONG_RUNS.md)).

## What it does

Hooks `session_before_compact`, calls Pi's own `compact()` with focus instructions plus
a retry policy, and returns the result as the compaction.

That's the whole extension. The value is in the instructions
([`instructions.ts`](extensions/context-handoff/instructions.ts)), which tell the
summarizer to preserve the objective, constraints, done-versus-remaining with a concrete
next action, durable specifics, and ruled-out approaches — and to state plainly that the
task is unfinished rather than reading as a conclusion.

## What it deliberately does not do

It **cannot stop a run**. It never calls `ctx.abort()`, never sends a message, never
returns `{ cancel: true }`, and never injects a resume prompt.

Every failure path returns `undefined`, which means "Pi, do your own compaction" — exactly
what happens with this package uninstalled. A missing model, unreadable config, provider
outage, empty summary, or aborted signal all degrade to native compaction with Pi's own
retries. The worst outcome is a less useful summary.

This matters because Pi already compacts and resumes on its own: when `_checkCompaction`
returns true, `_runAgentPrompt`'s loop calls `agent.continue()`. There is no turn to abort
and no resume to dispatch, so the machinery that made the previous extension fragile has
nothing to do.

Note the check runs *after* an agent run returns, not inside one — so it cannot stop
context from overshooting the window during a single long run. Nothing in this extension
can change that; see [`docs/LONG_RUNS.md`](../../docs/LONG_RUNS.md).

## Resuming a run Pi abandoned

There is one case where Pi compacts and then does *not* resume, and this extension fixes
it. When context leaves no room to generate, the reply is truncated: `stopReason "length"`,
an empty thinking block, no tool call, work unfinished. Pi's overflow test misses that
shape — it requires `usage.output === 0` and ≥99% of the window, and the real messages
carry a few reasoning tokens at ~98.4% — so it compacts as a routine threshold and ends
with `return this.agent.hasQueuedMessages()`, which is false. The run stops silently.

`session_compact` is emitted before that return, so a message queued there makes Pi call
`agent.continue()` instead. Observed in production: in one session a monitor event landing
28 ms after such a compaction resumed the run for another 600 entries, while an identical
compaction with nothing queued sat dead for 64 minutes.

So on `session_compact`, when the compaction followed a truncated assistant message and Pi
is not already retrying, this extension injects a resume message. It is narrow by design —
a normally finished turn is never nudged — and it stops after three consecutive truncated
resumes, saying why rather than looping. The logic is in
[`extensions/context-handoff/resume.ts`](extensions/context-handoff/resume.ts) and is unit
tested in [`tests/resume.test.ts`](../../tests/resume.test.ts).

## Configuration

All keys are optional. Configuration is read relative to `PI_CODING_AGENT_DIR`:

- `pi`: `~/.pi/agent/extensions/pi-context-handoff.json`
- `p`: `~/.pi/agent-p/extensions/pi-context-handoff.json`

The profiles use separate files; main-profile customization does not automatically apply
to `p`.

```json
{
  "enabled": true,
  "focus": "",
  "retry": { "enabled": true, "maxRetries": 3, "baseDelayMs": 2000 },
  "notifyOnFallback": true
}
```

- `focus` — extra sentences appended to the instructions, for project-specific priorities.
- `retry` — passed to Pi's `compact()`. Defaults mirror Pi's own retry settings.
- `notifyOnFallback` — warn once per session when a brief could not be produced.

Any `customInstructions` Pi was already going to use (a `/compact` argument, or another
extension's contribution) are preserved and appended, not overridden.

## When compaction happens

This package does not decide that; Pi does. Tune it with Pi's own settings:

```json
{ "compaction": { "enabled": true, "reserveTokens": 16384, "keepRecentTokens": 20000 } }
```

Compaction triggers when context exceeds `contextWindow - reserveTokens`. Keep
`reserveTokens` well below the model's context window — setting it near the window
produces a summarization request that can stall.
