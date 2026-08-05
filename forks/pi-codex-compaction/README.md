# pi-codex-compaction

Compacts context **inside** a run, before every LLM call, the way Codex does — instead of
only between runs, the way Pi does.

First-party extension, not a fork. It complements
[`../pi-context-handoff`](../pi-context-handoff/README.md) rather than replacing it.

## The gap

Pi evaluates its compaction threshold in exactly two places, both **outside** an agent run:
`_handlePostAgentRun`, after `agent.prompt()` has returned, and again before a new prompt.
Everything in between — every LLM call and tool result of one long autonomous run —
accumulates with no check at all. That is how a run reaches 120% of its context window and
then dies on a truncated reply.

`ctx.compact()` cannot close the gap: it begins with `_disconnectFromAgent()` and `abort()`,
so calling it mid-run kills the run it was meant to save.

Codex has no such gap. `codex-rs/core/src/session/turn.rs:493`:

```rust
if token_limit_reached && needs_follow_up {
    run_auto_compact(..., CompactionPhase::MidTurn).await?;
    continue;                       // the turn simply carries on
}
```

Compaction is a *step in the loop*, not a verdict on whether the loop survives.

## The mechanism

Pi's `context` hook is documented as *"fired before each LLM call. Can modify messages"*, and
the array a handler returns is what the provider actually receives
(`agent-loop.js:181` — `messages = await config.transformContext(messages, signal)`). That is
the same position in the loop as Codex's check, so the decision is made there.

When the request would exceed the trigger, the old part of the history is replaced with:

1. a summary of it, as Pi's own `compactionSummary` message,
2. the user's instructions from that stretch, **verbatim**,
3. the recent tail, untouched and passed through by reference.

## What matches Codex, and what doesn't

| | Codex | Here |
|---|---|---|
| When | After every sampling request | Before every LLM call — **equivalent**, see below |
| Trigger | 90% of the window, config can only lower it | Same, same clamp |
| Trigger input | Last response's total tokens + estimate of items since | Same, with an estimate-only fallback |
| User instructions | Verbatim, 20k token budget, oversized ones truncated | Same |
| Recent tail kept | **None at all** | **20k tokens**, surrendered under pressure |
| Initial context | Re-injected before the last user message | In Pi's system prompt, never touched |
| Smaller model selected | Compact with the *previous*, wider model | Same |
| Summarizer overflows | Drop oldest item, retry, until 1 item left | Drop oldest 25%, retry, ×5 |
| Other summarizer error | Backoff and retry, then fail | Same, via Pi's retry policy |
| Repeated compaction | No guard needed; reduces to ~20k | Stands down after 2 folds without progress |
| Persistence | Rewrites session history | **Shapes one request only** |
| On failure | Ends the turn (`turn.rs:504`) | **Sends the original history** |

**The recent tail is the one substantive divergence.** Codex's compacted history is initial
context, user messages and the summary, and *nothing else* —
`build_compacted_history(Vec::new(), ...)` starts from empty, so every assistant message and
tool result is discarded. This port keeps 20k tokens of recent conversation, for two reasons.
Pi's own compaction keeps a tail (`keepRecentTokens`, `retainedTail`), so it is the shape a
Pi-configured model already knows; and a *mid-flight* fold that dropped the tail would have the
model resume a tool sequence with no record of the results it just received, where Codex can
lean on a model trained for its own mid-turn shape and on putting the summary last. When
keeping the tail is what makes the request oversized, it is given up in stages — half, a
quarter, then entirely — because it is this port's addition, not a guarantee worth defending
past the point of failure.

**Timing is equivalent, not merely similar.** Codex checks after a response and compacts before
the next sampling request; the `context` hook fires before each LLM call. Those coincide,
including the gating: Codex compacts mid-turn only when `needs_follow_up`, and when a response
is final there is no next call, so the hook does not fire either. Codex's separate pre-turn
check corresponds to the hook firing before a turn's first call, and to Pi's own between-runs
check.

**Failure asymmetry is the central trade.** Because the hook shapes a single request rather
than rewriting state, nothing is destroyed and every failure path — no credential, empty
summary, provider outage, aborted signal, nothing left to fold, three failures in a row —
returns the messages Pi handed in. That is byte-for-byte the behaviour of not installing this
package. Codex is the stricter design and earns persistence for it; this one cannot make a run
worse than it already was, and in exchange never guarantees a fold.

Two consequences worth knowing:

- **The session file keeps everything.** Only what is *sent* shrinks. Pi's footer therefore
  keeps reporting the full history size while the actual request is small, which looks wrong
  and is not. `/codex-compaction` shows what is really being sent.
- **The fold is recomputed every call**, so the synthetic messages are frozen at creation —
  summary, pinned text and timestamp alike — because a prefix that changed between calls
  would lose provider prefix caching on every one of them.

Ordering differs from Codex deliberately: Codex appends the summary *last*, because its model
is trained to see it there after a mid-turn compaction. Pi's native compaction puts the
summary first and the retained tail after it, so that is the shape a Pi-configured model
already knows. For the same reason the pinned instructions are wrapped in one framed message
explaining that they are a record rather than a new request; Codex replays bare user messages
and relies on training to make that unambiguous.

## Known residual risks

From the adversarial pass over this package against Codex. These are real and unfixed, not
oversights:

- **Reasoning-item chaining in the tail.** The kept tail can begin with an assistant message
  whose reasoning items refer to a context that has been folded away. Some providers are strict
  about that. Pi's own compaction produces the same shape, so this is not new exposure, and the
  configured provider (`openai` / `gpt-5.6-sol`, reasoning `medium`) was verified to accept it —
  but it is provider-dependent and a stricter one could reject it. Codex sidesteps it by keeping
  no assistant messages at all.
- **The estimate path under-reports by roughly 15%.** Measured: a fold estimated 7,872 tokens
  where the provider then reported 9,442, because `toolOverheadTokens` understates real tool
  schemas. It matters little because the trigger normally reads a real usage record; the estimate
  is only used before the first response and for the "after" figure in reporting. Codex has no
  estimate-only path to get wrong.
- **An oversized *final* message cannot be folded.** Nothing can fold away the message the model
  still needs, so the honest outcome is no fold and Pi's own overflow recovery takes over. Codex
  survives this case because it truncates user messages into its verbatim budget; here the tail
  is kept whole.
- **Images in the folded prefix are lost**, since only text is pinned. Codex does the same
  (`content_items_to_text` skips `InputImage`).
- **`appendEntry` writes a session entry mid-stream.** Verified working twice, wrapped so a
  failure cannot affect the request, but it is a write on the streaming path.

One risk that was investigated and found not to exist: registering a `context` handler does
**not** make Pi start deep-cloning the history. `transformContext` calls `emitContext`
unconditionally and the `structuredClone` there precedes any handler check, so that cost is
Pi's on every LLM call whether or not this package is installed.

## Relationship to Pi's own compaction

Complementary, not competing:

- **This** keeps a *single long run* inside the window. Non-destructive, so history is intact
  when the run ends.
- **Pi's own**, between runs, is what genuinely shrinks history — and is still wanted.
  `pi-context-handoff` shapes that summary into a handoff brief.

When Pi compacts natively, the fold's fingerprints stop matching and it is discarded, so the
better, persistent compaction supersedes it.

## Configuration

Optional, read relative to `PI_CODING_AGENT_DIR`:

- `pi`: `~/.pi/agent/extensions/pi-codex-compaction.json`
- `p`: `~/.pi/agent-p/extensions/pi-codex-compaction.json`

```json
{
  "enabled": true,
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
  "focus": "",
  "retry": { "enabled": true, "maxRetries": 3, "baseDelayMs": 2000 }
}
```

- `triggerPercent` — **clamped to 0.9**, matching Codex's `min(config_limit, window * 9 / 10)`.
  A configured value can only make it fold *earlier*. Folding later than 90% is the one
  setting there is no recovering from.
- `keepRecentTokens` — recent conversation left untouched.
- `pinUserTokens` — budget for verbatim user instructions. `0` disables pinning.
- `minSavingTokens` — below this a fold is not worth a summarization call.
- `toolOverheadTokens` — stands in for tool schemas, which appear in every provider usage
  number and in no message. Without it the estimate path and the usage path would answer to
  different thresholds. The system prompt is measured directly via `ctx.getSystemPrompt()`.
- `maxFailures` — consecutive failed folds after which the extension stands down for the
  session.
- `maxFoldsWithoutProgress` — folds allowed without the request dropping under the trigger.
  Folding that is not achieving its purpose only costs context, so it stops. Codex needs no
  equivalent because its compaction reduces to roughly 20k, far below any trigger — its own
  comment says an infinite loop is therefore not a concern. Keeping a recent tail is what makes
  the guard necessary here.
- `focus` — extra sentences for the summarizer, for project-specific priorities.

`PI_CODEX_COMPACTION_FORCE_TRIGGER_TOKENS=<n>` replaces the trigger with an absolute token
count. A 245,000-token conversation cannot be produced on demand, so this is how a real fold
is exercised end to end.

## Layout

- [`fold.ts`](extensions/codex-compaction/fold.ts) — every decision, pure and injected with
  its token metrics. Unit tested in [`tests/codex-compaction.test.ts`](../../tests/codex-compaction.test.ts).
- [`index.ts`](extensions/codex-compaction/index.ts) — the hook, credentials, summarization,
  failure handling.
- [`instructions.ts`](extensions/codex-compaction/instructions.ts) — summarizer focus, written
  for a mid-flight cut rather than a turn boundary.
- [`config.ts`](extensions/codex-compaction/config.ts) — config loading; never throws.
