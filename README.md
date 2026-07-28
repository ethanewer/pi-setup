# pi-process-monitor-safe

> Safety-hardened **local fork** of [`pi-process-monitor`](https://github.com/Fornace/pi-process-monitor) 1.2.0 (MIT © Francesco Frapporti). Non-blocking background watchers for [pi](https://pi.dev): start a process, an SSH poll, or a log tail and get **pinged in-session** on milestones, failures, exit, or aggregated heartbeats — without blocking.

This fork **replaces** the upstream package. Do **not** load it alongside `npm:pi-process-monitor`: tool and command names collide by design.

## What changed vs upstream 1.2.0

| Area | Upstream 1.2.0 | This fork |
|------|----------------|-----------|
| Watcher limit | unbounded | hard cap of **16 active watchers**, enforced synchronously in the shared `launch()` path (tools and commands both) |
| Kill-all | — | new `monitor_kill_all` tool and `/monitor-kill-all` command |
| Persistence / restore | poll & file watchers persisted via `appendEntry` and re-launched on `session_start` | **never persisted, never restored**; legacy `monitor-watcher` entries in old sessions are ignored |
| Session shutdown | best-effort `w.stop()`, killed spawn still emitted a "killed" exit turn | all watchers stopped atomically; one consolidated, reason-aware (`quit`/`reload`/`new`/`resume`/`fork`) custom message persisted synchronously; **never wakes the model** |
| Fork | resumed watchers duplicated into forks | forks get one no-turn context note that source-session monitors were not carried over |
| Heartbeats | one `setInterval` + turn per watcher | **one extension-level scheduler** (30s tick) aggregates all due watchers into a single turn-triggering `monitor-heartbeat` message; a real event within the preceding interval substitutes for that heartbeat |
| Killed processes | `SIGTERM` to direct child only; exit event still woke the model | process-**group** SIGTERM with bounded SIGKILL escalation (3s); killed exits are silent; slots release immediately |
| Poll mode | per-chunk line handling, unbounded rolling dedup churn, in-flight polls leaked on stop | complete-line assembly across chunks, bounded retained output, complete-line-set diff vs the previous poll, in-flight poll children terminated on stop |
| Spawn matching | every stdout/stderr line was pushed (ignored `notifyOn`) | `notifyOn` matcher applied in spawn mode too, as documented |
| Stopped watchers | lingered in the status map | map membership *is* liveness: stopped/exited watchers disappear from `monitor_status` and free their slot |

## Install (local package)

Add the package path to your pi settings (`~/.pi/agent/settings.json`), and make sure `npm:pi-process-monitor` is **not** also listed:

```json
{
  "packages": ["/Users/you/.pi/agent/local/pi-process-monitor-safe"]
}
```

## Three sources (pick one)

| mode | tool params | command equivalent | use case |
|------|-------------|--------------------|----------|
| **spawn** | `command` | `/monitor <cmd>` | local long job — spawned once, tailed until exit |
| **poll** | `command` + `intervalSeconds` | `/monitor --poll --every 30 -- <cmd>` | **remote/SSH** — re-run a check on a cadence |
| **file** | `logFile` | `/monitor --file <path>` | tail appended lines of a log |

## Tools

### `monitor` — start a watcher
```json
{
  "command": "ssh h100 'tail -n3 /root/train.log; echo ALIVE=$(pgrep -fc axolotl)'",
  "intervalSeconds": 30,
  "label": "h100-qlora",
  "heartbeatMinutes": 10,
  "notifyOn": ["adapter.*saved", "error|oom|killed|traceback", "ALIVE=0"]
}
```

Params: `command`, `intervalSeconds` (min 2), `logFile`, `notifyOn` (case-insensitive regexes), `heartbeatMinutes`, `label`, `coalesceSeconds` (default 2), `maxLines` (default 20), `cwd`, `timeoutSeconds`.

Starting a 17th watcher fails with an **error** tool result:

```
16 active monitors; use monitor_status, then monitor_kill (or monitor_kill_all) before starting another.
```

### `monitor_status` — list active watchers
Only *active* watchers appear; stopped and exited watchers free their slot immediately.

### `monitor_kill` — stop one watcher
Signals the child's process group with SIGTERM, escalating to SIGKILL after 3s. The slot is freed immediately; the killed process does **not** produce an exit turn.

### `monitor_kill_all` — stop everything
Stops every active watcher atomically and returns the consolidated list in the tool result (no duplicate context message).

## Slash commands

```bash
/monitor ssh h100 'tail -n3 train.log; pgrep -fc axolotl'   # spawn watcher
/monitor --poll --every 30 -- ssh h100 'tail -n3 train.log' # poll every 30s
/monitor --file /var/log/train.log                          # tail a log
/monitor --timeout 3600 -- long-job.sh                      # auto-kill after 1h
/monitors                                                   # list
/monitor-kill <TAB>                                         # autocomplete live ids
/monitor-kill-all                                           # stop everything
```

`/monitor-kill-all` shows one UI notification per stopped watcher and appends **one** consolidated custom message so the model knows the watchers are gone — without triggering a model turn.

## Context semantics

- **Turn-triggering** (`triggerTurn: true`, delivered as steer): matched lines (coalesced), natural process exits, timeouts, and requested heartbeat aggregates.
- **Context-only, never wakes the model**: `/monitor-kill-all` summaries, session-shutdown summaries, and the fork note.
- All emitted content is tail-truncated to bounded lines and bytes.

## Heartbeats

Off unless `heartbeatMinutes` is set. One extension-level scheduler ticks every 30s; every watcher due on a tick is folded into **one** `monitor-heartbeat` message (`details: { watcherIds }`) that triggers a single model turn, then each watcher's due time advances by its own interval. A real matched/exit event during a watcher's preceding interval substitutes for that heartbeat. Heartbeats never count as real events in `monitor_status`.

## Session lifecycle (breaking change vs upstream)

**Watchers do not survive session shutdown, `/reload`, `/new`, `/resume`, or `/fork` — by design.** Watcher definitions are executable state and are never written to the session file, so nothing can be restored (or resurrected unexpectedly) later. On shutdown, every watcher is stopped and one reason-aware summary is persisted into model context, so a later resume of the session knows the watchers no longer exist and can restart them. On idle shutdown the summary goes through `pi.sendMessage` (no `triggerTurn`); if shutdown happens mid-stream it is appended directly through the session manager so it cannot be stranded in the steer queue. A hard process crash cannot append a summary, but nothing restarts either way.

## Pitfalls

- **Don't** wrap a `monitor` call in a blocking `bash` wait — `monitor` returns immediately; trust the ping.
- For **poll mode**, the `command` must be *idempotent and fast* (a tail + a process check); the long job runs separately on the remote.
- Always include a **death signal** in `notifyOn` for poll/file mode (e.g. `ALIVE=0`).
- After `/reload` or resuming a session, monitors are gone — recreate the ones you need.

## Development

```bash
npm install        # dev/peer deps
npm run typecheck  # tsc --noEmit
npm test           # node --test (deterministic fakes + one real-child smoke test)
```

The runtime is built around injected clock, process (spawn/group-kill), and filesystem adapters (`extensions/monitor/types.ts`), so the entire lifecycle — limits, kills, coalescing, heartbeats, shutdown — is unit-tested with fake timers and scripted children in `test/`.

## License

MIT. Original work © 2026 Francesco Frapporti (`pi-process-monitor`); fork modifications © 2026 the pi-process-monitor-safe authors. See [LICENSE](LICENSE).
