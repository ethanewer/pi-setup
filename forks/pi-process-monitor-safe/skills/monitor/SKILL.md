---
name: monitor
description: Non-blocking watcher for long jobs (builds, tests, training, dev servers, remote SSH, log tails). Pings the session on milestones/failures so you keep working instead of blocking.
user-invokable: true
tested_date: 2026-07-28
tested_with: pi-process-monitor-safe 1.0.0, @earendil-works/pi-coding-agent (peer)
---

# monitor — non-blocking background watcher (safe fork)

Conditional delivery: only lines matching `notifyOn` (default: milestones +
failures) plus process-exit get pushed to the session, instead of one LLM turn
per stdout line. Rapid matches are coalesced. Keeps context lean and the
session unblocked.

## The rule after starting one

`monitor` returns in milliseconds. When it does, say one line of status and **end
your turn** — the matching ping starts your next turn automatically. Never follow a
`monitor` call with `sleep`, wait loops, or repeated `tail`/`curl` checks; that
re-blocks exactly what the watcher exists to prevent. If you have other work, do it
now; otherwise stop and wait for the ping.

## When to use this

Any task that could plausibly run **longer than a few seconds** AND you want to
keep chatting / doing other work instead of blocking:

- **ML training** (axolotl, vLLM, accelerate, torchrun) — ping on adapter-saved / OOM / step walls
- **Remote SSH jobs** — poll a box every N seconds (`ssh h100 'tail; pgrep'`)
- **Dev servers / builds** — ping on "listening", crash, or first error
- **CI / long tests / migrations**
- **Log tails** — watch a file for appended milestone/error lines
- **Fix-and-rerun loops** — watch every run, including ones you expect to fail;
  the crash/traceback lines become pings
- **Work while waiting** — start the watcher, then do the task's other work; the
  ping brings you back when the job finishes
- **Periodic check-ins on quiet jobs** — `heartbeatMinutes` pings on schedule even
  when nothing matches (progress-bar output, silent training runs)

If it's under ~10s, just run it inline (bash). If it might run
minutes-to-hours, use `monitor`.

## Three sources (pick one)

| mode | tool params | command equivalent | use case |
|------|-------------|--------------------|----------|
| `spawn` | `command` | `/monitor <cmd>` | local long job — spawned once, tailed until exit |
| `poll` | `command` + `intervalSeconds` | `/monitor --poll --every 30 -- <cmd>` | **remote/SSH** — re-run a check on a cadence |
| `file` | `logFile` | `/monitor --file <path>` | tail appended lines of a log |

## The default `notifyOn` (regex, case-insensitive)

milestones: `saved`, `checkpoint`, `complete(d)`, `done`, `finished`, `ready`,
`started`, `listening`, `success`, `ok`, `✓`, `✔`
failures: `error`, `fail(ed)`, `oom`, `out of memory`, `killed`, `traceback`,
`exception`, `fatal`, `abort`, `panic`, `segfault`

Override per-call with `notifyOn: [...]` (regexes). Always include a
death/exit signal for poll mode, e.g. an `ALIVE=0` sentinel.

## Limits (important)

At most **16 watchers** can be active at once. The 17th `monitor` call fails
with an error telling you to run `monitor_status`, then `monitor_kill` (use
`id: "*"` to stop everything). Stopped and exited watchers free their slot
immediately, so clean up watchers you no longer need.

## Recipes

### ML training on a remote H100 (the canonical case)
```json
{ "command": "ssh h100 'tail -n3 /root/train.log; echo ALIVE=$(pgrep -fc axolotl)'",
  "intervalSeconds": 30, "label": "h100-qlora",
  "notifyOn": ["adapter.*saved", "step (6[0-9]|[1-9][0-9][0-9]) ", "error|oom|killed|traceback", "ALIVE=0"] }
```
Returns at once (`Watcher <id> running`). You keep working. The session is
pinged when the adapter saves, when step 60+ lands, on OOM, or when the
process dies.

### Local dev server (spawn)
```json
{ "command": "cd app && npm run dev", "label": "dev",
  "notifyOn": ["listening|ready|started", "error|EADDR|crash"] }
```

### Tail an existing log
```json
{ "logFile": "/var/log/train.log", "notifyOn": ["loss=", "OutOfMemory", "Killed"] }
```

## Timeout

Auto-kill a watcher after N seconds — available through the `/monitor`
command (`--timeout N`), not as a tool parameter. Fires a `TIMEOUT after Ns`
ping and stops the watcher cleanly.

## Heartbeats

Set `heartbeatMinutes` on a watcher (fractional allowed: `0.5` = 30 s) to get a
status ping on schedule even when nothing matches — the right tool for periodic
check-ins on quiet jobs. Due heartbeats from all watchers are aggregated into a
single `monitor-heartbeat` ping that wakes the session once; a real event during
the preceding interval substitutes for that heartbeat. On a heartbeat ping, reply
with a brief status and end your turn.

## Lifecycle

- `monitor_status` / `/monitors` — list ACTIVE watchers (id, mode, events,
  last ping). Stopped/exited watchers are removed immediately.
- `monitor_kill {id}` / `/monitor-kill <id>` — stop one (`/monitor-kill <TAB>`
  autocompletes live ids; the child's process group gets SIGTERM, then
  SIGKILL after 3s); pass `id: "*"` to stop ALL watchers atomically
  (`/monitor-kill-all` does the same for humans). Killed processes do not
  produce an exit ping.
- **No restart-resume (differs from upstream):** watchers are never persisted
  and never restored. Session shutdown, `/reload`, `/new`, `/resume`, and
  `/fork` stop all watchers and record one context summary naming the reason.
  Recreate any monitor you still need afterwards.

## How the ping works (don't fight it)

- Idle agent → the matching message triggers a fresh turn (agent wakes, reads
  the pushed lines, acts).
- Mid-stream agent → the message queues as a steer, delivered after the
  current turn's tool calls, before the next LLM call.
- Rapid matching lines are **coalesced** into one message (default 2s window,
  max 20 lines) so a chatty log doesn't flood context.

## Pitfalls

- **Don't** wrap a `monitor` call in a blocking `bash` wait — that defeats the
  point. `monitor` returns immediately; trust the ping.
- For poll mode, your `command` must be **idempotent and fast** (a tail + a
  process check). Don't put the actual long job in the poll command. A tick that has not
  finished one second before the next interval is killed and reported as
  `POLL TIMEOUT after <n>s`, so a hung SSH costs one tick instead of silencing the
  watcher; polling continues on the next interval.
- Always include a death signal in `notifyOn` for poll/file mode (e.g.
  `ALIVE=0`), otherwise a silently-dead remote job won't ping you.
- Default `notifyOn` is broad. For chatty logs, pass a tight `notifyOn`.
- After `/reload` or a session switch, monitors are gone — restart them.
- **Progress bars are invisible.** Matching is line-oriented, so a job that redraws one
  line with carriage returns (`tqdm`, `wget`, `docker pull`, most training loops) produces
  no complete line and can never match any pattern. The watcher looks like it is waiting
  patiently while it is actually blind. If that happens you get one event:

  ```text
  [watcher <id>] NO LINE BREAK in 65536 bytes of output. ...
  ```

  It fires once per watcher, never repeats, and means the watcher cannot see this output.
  Fix it at the source — have the job print its own newline-terminated markers, which is
  what you want anyway:

  ```bash
  python train.py 2>&1 | tee /tmp/train.log
  echo "TRAIN_COMPLETE rc=$?"        # a real line the watcher can match
  ```

  Or watch it with poll mode, which re-runs a cheap check on an interval instead of tailing
  the stream. Do not try to match text inside the bar.
