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

## Configuration

`~/.pi/agent/extensions/pi-btw-side.json`, all keys optional:

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
