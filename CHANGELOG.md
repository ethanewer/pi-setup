# Changelog

## 1.0.0 (2026-07-28)

Initial release of the safety-hardened local fork of `pi-process-monitor@1.2.0`
(MIT © Francesco Frapporti). This package **replaces** the upstream package;
loading both is unsupported (tool/command names collide).

### Added
- `monitor_kill_all` tool and `/monitor-kill-all` command: stop every active
  watcher atomically. The command emits one UI notification per stopped
  watcher plus one consolidated, non-turn-triggering custom message; the tool
  returns the same consolidated list in its result.
- Hard cap of 16 active watchers, enforced synchronously inside the shared
  `launch()` path. The tool path throws (isError result with actionable
  text); the `/monitor` command shows the same message as a UI warning.
- Aggregated heartbeats: one extension-level 30s scheduler emits a single
  turn-triggering `monitor-heartbeat` message (`details: { watcherIds }`) for
  all due watchers; per-watcher due times advance by their own intervals; a
  real event within the preceding interval substitutes for that heartbeat.
- Reason-aware session-shutdown summary (`quit`/`reload`/`new`/`resume`/
  `fork`) persisted synchronously as one model-visible custom message that
  never triggers a turn; appended directly through the session manager when
  shutdown happens mid-stream.
- Fork note: `session_start` with `reason: "fork"` appends one no-turn
  context note that source-session monitors were not carried over.
- Injected clock/process/filesystem adapters plus a comprehensive
  deterministic test suite (fake timers, scripted children, mock
  ExtensionAPI) and real-child integration smoke tests (final output is
  delivered before the exit event; stopping a watcher kills the whole
  process group).

### Changed
- Stopped and naturally exited watchers are removed from the active map
  immediately: they disappear from `monitor_status` and release their slot at
  once (no 3s SIGKILL wait).
- Teardown signals the child's process group (`detached` + negative-PID
  SIGTERM, bounded SIGKILL escalation after 3s), falling back to direct-child
  signaling where groups are unavailable. In-flight poll children are
  terminated too. On `quit` shutdown the SIGKILL follows SIGTERM immediately,
  because the Pi process exits before any escalation timer could fire.
- Child exit handling waits for Node's `close` event (all stdio delivered)
  instead of `exit`, so final output written just before termination is never
  dropped; exit code/signal are tracked and exit callbacks fire exactly once.
  Errored children are always untracked, so failed handles cannot accumulate.
- Killed/timeout/shutdown process exits no longer emit a second
  process-exit message; only natural exits do.
- Poll mode assembles complete lines across chunks, bounds retained output,
  and diffs complete line sets against the previous poll instead of replaying
  identical old lines. Repeated spawn/runtime failures are latched: only the
  first consecutive failure emits an event; the latch re-arms after a poll
  completes successfully.
- File mode buffers a partial trailing line across reads until its newline
  arrives (bounded to 64 KiB), reads at most 256 KiB per pass (larger bursts
  skip ahead to the tail), and drops the held partial line on rotation.
- A synchronous spawn failure makes `launch()` clean up the reserved slot and
  throw — the `monitor` tool returns an error result instead of reporting a
  never-started watcher as running. Asynchronous spawn errors still emit one
  `SPAWN ERROR` event and release the watcher.
- `/monitor` only interprets the ` -- ` separator when monitor flags
  (`--poll`, `--file`, `--every`, `--timeout`) are present; plain commands
  containing ` -- ` are preserved verbatim.
- Watcher ids are guarded against random-id collisions (regenerate, then
  force a unique suffix).
- Spawn mode now applies the `notifyOn` matcher (upstream pushed every line,
  contradicting its own documentation).
- Every timer/child/file callback re-checks watcher liveness before emitting,
  so no queued or coalesced message escapes after a kill or shutdown.

### Removed
- Watcher persistence and restart-resume: watcher definitions are never
  written via `appendEntry`, and `session_start` never scans or restores
  historical watchers. Legacy `monitor-watcher` entries in existing session
  files are inert and ignored.
