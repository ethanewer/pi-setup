# pi-btw-inline

Codex's `/side` — the command it also aliases as `/btw` — for Pi, rendered inline.

```
/btw is this migration reversible?
```

The question is answered in an **ephemeral fork** of the current conversation. The model
sees everything said so far as reference context, answers, and none of it — question or
answer — ever enters the main thread's context. The main thread does not pause, and does
not have to be idle: `/btw` works mid-turn, which is the case it exists for.

There is no overlay. The answer lands in the transcript as a custom entry, which Pi
renders inline and never sends to a model.

## Commands

| Command | Effect |
|---|---|
| `/btw <question>` | Fork, ask, and stay in the side conversation |
| `/btw` | Open a side conversation without asking anything yet |
| `/btw:end` | Discard the side conversation and return to the main thread |

While a side conversation is open the footer reads `btw · side thread`, and typed
messages go to it rather than to the main agent — the same sticky behaviour Codex has,
where you leave with `Ctrl+C`. `/btw:end` is the way out here, and it also cancels an
answer that is still being written.

Slash commands still reach Pi normally while side mode is open, so `/model`, `/tree`, and
the rest behave as usual. Skills and prompt templates are refused with a message: Codex
disables them inside a side conversation for the same reason, which is that expanding one
there is never what the user meant.

## What matches Codex, and what does not

Matched, from `codex-rs/tui/src/app/side.rs`:

- The fork inherits the parent's history, its model, its thinking level, and its project
  context (system prompt, `AGENTS.md`).
- The same boundary prompt is prepended to the first question, and the same developer
  instructions are appended to the system prompt: inherited history is reference material,
  only messages after the boundary are live instructions, sub-agents are off-limits, and
  nothing is mutated unless the user asks for it in the side conversation.
- The fork is ephemeral. It has no session file, and it is discarded on `/btw:end`,
  session switch, or shutdown.
- Nothing is carried back automatically. Copy anything you want to keep.

Deliberately different:

- **No overlay.** The exchange renders inline in the transcript, collapsed past 14 lines
  and expandable like any other entry. This is the reason the package exists.
- **Read-only tools by default.** Codex keeps the parent's tools and relies on the
  instructions to stay non-mutating. A Pi side thread runs without an approval prompt in
  front of it, so the restriction is structural here: `read`, `grep`, `find`, and `ls`.
  Set `"toolset": "full"` for Codex's behaviour (adds `bash`, `edit`, `write`), or
  `"none"` for a thread that can only reason about what it already sees.
- **The exchange is written to the local session file** as a custom entry, so it survives
  a reload and stays in the scrollback. Custom entries never participate in LLM context —
  the model cannot see it — but "ephemeral" here means "invisible to the model", not
  "unrecoverable from disk".

## Configuration

`~/.pi/agent/extensions/pi-btw-inline.json`, all keys optional:

```json
{
  "enabled": true,
  "sticky": true,
  "toolset": "readonly",
  "model": null,
  "thinkingLevel": null,
  "timeoutMs": 600000,
  "livePreview": true,
  "previewLines": 6
}
```

- `sticky` — `false` makes `/btw` a one-shot question: the fork is discarded as soon as
  the answer arrives, and typed messages always go to the main thread. Sticky mode is
  never enabled outside the TUI, where there would be no way to see or leave it.
- `toolset` — `"readonly"` (default), `"full"`, or `"none"`.
- `model` — `"provider/model-id"`, e.g. `"openai/gpt-5.6-sol"`. A cheaper model for side
  questions is the usual reason. Null inherits the main thread's model, as Codex does; an
  unresolvable entry falls back to it rather than failing the command.
- `thinkingLevel` — `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, or `max`.
- `timeoutMs` — a side turn that runs this long is aborted. `0` disables it.
- `livePreview` / `previewLines` — the streaming preview shown above the editor while the
  answer is being written.

A malformed config file degrades to these defaults with a warning; it never breaks the
command.

## Why it cannot stop a long run

The side thread is a separate `AgentSession` with its own in-memory session manager. It
cannot abort the main turn, cannot write to the main session's context, and its failures
are reported as a notification and a transcript entry rather than raised into Pi's event
loop. The command never blocks Pi's input loop either: in the TUI the turn is dispatched
and the composer stays live, which is also what makes `/btw:end` able to cancel it.

The one place the side thread touches shared state is the file system, when `toolset` is
`"full"` and the model is asked for a mutation. That is why the default is read-only.
