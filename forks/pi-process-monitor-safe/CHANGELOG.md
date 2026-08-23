# Changelog

## 1.1.0 (unreleased, monitor-optim branch)

Model-surface simplification (backend behavior unchanged; validated with the
monitor-bench evals across four models x three seeds: trust 32/48 -> 38/48).

### Changed
- `monitor_kill_all` merged into `monitor_kill`: `id: "*"` intentionally stops
  all active watchers and returns the consolidated list.
- `monitor` tool schema trimmed to six parameters (`command`,
  `intervalSeconds`, `logFile`, `notifyOn`, `label`, `cwd`); the removed
  knobs keep their defaults internally, and `--timeout N` remains on the
  `/monitor` command.
- `promptGuidelines` reduced from three to one; tool and skill descriptions
  shortened. SKILL.md adds an explicit end-your-turn rule plus a relative
  `logFile` path fix (resolved against the watcher cwd).
- `heartbeatMinutes` restored to the schema (single parameter, fractional
  minutes allowed): periodic check-ins on quiet jobs were otherwise
  unreachable after the trim.

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
  signaling where groups are unavailable. The fallback path escalates too:
  the real child handle no longer gates signals on `ChildProcess.killed`
  (which only records that a signal was sent), so a child that traps SIGTERM
  still receives the direct-child SIGKILL. In-flight poll children are
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
  identical old lines. When bounded retention truncates from the head, the
  potentially partial first retained line is discarded before matching/dedup.
  Poll ticks never overlap: a tick due while the prior poll child is still
  running is skipped. Repeated spawn/runtime failures are latched: only the
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
  containing ` -- ` are preserved verbatim. A bare `--every N` implies
  `--poll` (a cadence only makes sense for polling); `--file` takes
  precedence over both.
- `typebox` and `@earendil-works/pi-tui` (both imported by the extension and
  resolved from the pi host at runtime) are declared as `*` peerDependencies
  alongside `@earendil-works/pi-coding-agent`.
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
