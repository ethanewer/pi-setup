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

It **cannot stop a run**. It never calls `ctx.abort()` and never returns
`{ cancel: true }`.

It does send exactly one kind of message — a resume nudge, and only where Pi has already
decided to end the run. See [Resuming a run Pi abandoned](#resuming-a-run-pi-abandoned).
Earlier versions of this file said it never sends a message; that was true until the
resume was added, and the constraint it was protecting (this extension must not be able to
*stop* a run) still holds.

Every failure path returns `undefined`, which means "Pi, do your own compaction" — exactly
what happens with this package uninstalled. A missing model, unreadable config, provider
outage, empty summary, or aborted signal all degrade to native compaction with Pi's own
retries. The worst outcome is a less useful summary.

This matters because Pi already compacts and resumes on its own: when `_checkCompaction`
returns true, `_runAgentPrompt`'s loop calls `agent.continue()`. There is no turn to abort
and no resume to dispatch, so the machinery that made the previous extension fragile has
nothing to do.

Note the check runs *after* an agent run returns, not inside one — so it cannot stop
context from overshooting the window during a single long run. Nothing in this extension can
change that. [`pi-codex-compaction`](../pi-codex-compaction/README.md) is the companion that
does, by shrinking the request through the `context` hook rather than compacting; see
[`docs/LONG_RUNS.md`](../../docs/LONG_RUNS.md).

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

Truncation is only one of the ways Pi ends a run there. A compaction that threw, nothing to
compact, an aborted compaction, and spent overflow recovery all return false the same way —
and three of those never emit `session_compact` at all. So this extension resumes at two
points: `session_compact` when it can (cheapest, continues the same run), and `agent_settled`
as a backstop, which Pi emits from `_runAgentPrompt`'s `finally` on every stopping path.

Only `stopReason` `length` or `error` count as unfinished. `stop` and `aborted` are never
resumed — that gating is what keeps `agent_settled`, which fires after every run, from making
the agent chatter. It gives up after three consecutive unfinished resumes and says why.

`PI_CONTEXT_HANDOFF_FORCE_RESUME=1` forces the backstop once, which is how the injection is
verified end to end; a real context truncation cannot be produced on demand. The logic is in
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
{ "compaction": { "enabled": true, "reserveTokens": 68000, "keepRecentTokens": 20000 } }
```

Compaction triggers when context exceeds `contextWindow - reserveTokens`. Keep
`reserveTokens` well below the model's context window — setting it near the window
produces a summarization request that can stall. `install.sh` applies
[`config/compaction.json`](../../config/compaction.json), which sizes the reserve to cover
one whole agent run rather than one reply; see
[`docs/LONG_RUNS.md`](../../docs/LONG_RUNS.md) for why that matters and what it cannot
guarantee.
