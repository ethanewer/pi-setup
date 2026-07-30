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

This matters because Pi already compacts mid-turn and continues: `_checkCompaction`
returns true and the agent loop carries on. There is no turn to abort and no resume to
dispatch, so the machinery that made the previous extension fragile has nothing to do.

## Configuration

Optional, at `~/.pi/agent/extensions/pi-context-handoff.json`:

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
