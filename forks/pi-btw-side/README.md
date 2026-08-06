# pi-btw-side

Codex's `/side` — the command it also aliases as `/btw` — for Pi.

```
/btw is this migration reversible?
```

The screen switches to a clean side conversation: an **ephemeral fork** where the model
sees everything said so far as reference context, and where neither the question nor the
answer ever enters the main thread's context. **Escape** returns to the main thread and
discards the fork.

While the side view is open the main thread is not on screen — and it is still running.
Opening `/btw` in the middle of a long task neither pauses nor disturbs it; the header
reports whether it is still working, and its transcript is exactly where you left it when
you come back.

## Keys and commands

| | |
|---|---|
| `/btw <question>` | Open the side view and ask |
| `/btw` | Open the side view empty |
| `esc` | Return to the main thread, discarding the side conversation — including mid-answer |
| `shift+↑` / `shift+↓`, `pageup` / `pagedown` | Scroll the side transcript |

Inside the view, typing goes to the side thread — no prefix. A message sent while an
answer is still streaming is queued and answered next, not dropped. Pi's own slash
commands are not available there, which is also true in Codex.

Outside the TUI, `/btw <question>` answers once and prints the answer (print mode) rather
than opening a view.

## What matches Codex, and what does not

Matched, from `codex-rs/tui/src/app/side.rs`:

- The view starts clean. The inherited history is real context for the model but is not
  displayed, which is exactly Codex's `install_side_thread_snapshot`: *"the forked history
  remains available to the model through core state, but side conversations should
  visually start at the side boundary."*
- The fork inherits the parent's history, model, thinking level, and project context
  (system prompt, `AGENTS.md`).
- The same boundary prompt is prepended to the first question, and the same developer
  instructions are appended to the system prompt: inherited history is reference material,
  only messages after the boundary are live instructions, sub-agents are off-limits, and
  nothing is mutated unless the user asks for it in the side conversation.
- It is ephemeral. It has no session file, and it is discarded on exit.
- Nothing is carried back automatically. Copy anything you want to keep before leaving.
- Only one side conversation at a time.

Deliberately different:

- **Escape, not Ctrl+C, is the way out.** Codex leaves on Ctrl+C, but Pi claims that key
  for clear/exit and it never reaches a focused component, so escape is the exit here. It
  works mid-answer too: leaving discards the thread either way.
- **Read-only tools by default.** Codex keeps the parent's tools and relies on the
  instructions to stay non-mutating. A Pi side thread runs without an approval prompt in
  front of it, so the restriction is structural here: `read`, `grep`, `find`, and `ls`.
  Set `"toolset": "full"` for Codex's behaviour (adds `bash`, `edit`, `write`), or
  `"none"` for a thread that can only reason about what it already sees.
- **The main thread's status is on screen.** Codex shows parent status in the side view's
  footer; this shows `main thread: working` / `idle` in the header, driven by the host's
  own `agent_start` / `agent_settled` events.
- **The inherited history is capped.** Codex forks a persisted rollout that its own
  compaction has already shrunk. Pi checks its compaction threshold only *between* runs,
  and `/btw` is designed to be used *during* one, so the parent can be far past that
  threshold at the moment it is forked. See below.

## Why the inherited history is trimmed

Pi derives the output budget as `contextWindow - contextTokens - 4096`. Fork a parent
sitting near the top of its window and the side thread is handed almost nothing to answer
in — reasoning tokens come out of that same budget, so the model thinks until it runs out
and the reply stops mid-sentence with *"reached the maximum output token limit"*.

Reconstructed from a real session at the parent's worst turn — 269,066 tokens of a 272,000
window — the fork was being handed **`max_tokens = 1`**, the clamp's own floor. With the
cap in place the same fork gets **42,531**, after dropping the 11 oldest messages of 341.

Two things had to change together, and neither works alone:

- **The parent's `usage` figures are cleared.** Pi's estimator anchors on the newest
  assistant `usage` it can find, which in a fork describes the *parent's* request, not the
  fork's. It is completely insensitive to the fork's contents: on a real 797-message
  history, dropping the oldest half moved the estimate by exactly zero. Trimming against
  it could never have worked.
- **The history is then measured and cut** to leave a guaranteed output reserve — 32,768
  tokens, or 35% of the window on models too small for that. Oldest-first, since a
  follow-up question is usually about the recent end. It is re-checked before every turn,
  because the side thread's own answers accumulate and would otherwise walk it back into
  the same state.

A parent that comfortably fits is not touched at all. When anything is dropped the view
says so, because a silently shortened context reads as the model forgetting.

Inherited messages are flattened with Pi's `convertToLlm` before any of this. That is what
the provider is really sent, so it is the honest thing to measure — and it is required,
not cosmetic: a `compactionSummary` keeps its text in `summary` rather than `content`, and
a `custom` message's content can be a bare string, and Pi's own estimator throws on both.
It survives them today only because the `usage` anchor short-circuits before reaching
them, which is exactly what clearing the anchor stops it doing.

## Configuration

All keys are optional. Configuration is read relative to `PI_CODING_AGENT_DIR`:

- `pi`: `~/.pi/agent/extensions/pi-btw-side.json`
- `p`: `~/.pi/agent-p/extensions/pi-btw-side.json`

The profiles use separate files; main-profile customization does not automatically apply
to `p`.

```json
{
  "enabled": true,
  "toolset": "readonly",
  "model": null,
  "thinkingLevel": null,
  "timeoutMs": 600000,
  "record": false
}
```

- `toolset` — `"readonly"` (default), `"full"`, or `"none"`.
- `model` — `"provider/model-id"`, e.g. `"openai/gpt-5.6-sol"`. A cheaper model for side
  questions is the usual reason. Null inherits the main thread's model, as Codex does; an
  unresolvable entry falls back to it rather than failing the command.
- `thinkingLevel` — `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, or `max`.
- `timeoutMs` — a side turn that runs this long is stopped. `0` disables it.
- `record` — leave a collapsed card in the main transcript when the view closes, instead
  of discarding the conversation. The card is a custom entry, so no model ever sees it;
  this only decides whether *you* can scroll back to it.

A malformed config file degrades to these defaults with a warning; it never breaks the
command.

## Why it cannot stop a long run

The side thread is a separate `AgentSession` with its own in-memory session manager, and
the view is an overlay. Neither touches the host session: the main turn is not aborted,
not paused, and not added to. Opening, using, and closing the view is invisible to the
main thread apart from the screen it occupies.

Failures are reported inside the view rather than raised into Pi's event loop, and the
side turn has its own timeout. The one place the side thread touches shared state is the
file system, when `toolset` is `"full"` and the model is asked for a mutation — which is
why the default is read-only.
