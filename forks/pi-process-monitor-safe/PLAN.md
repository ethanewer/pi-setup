# Safe local fork plan

> **Status note (1.1.0):** this plan documents the original hardening pass and is
> historical. Two details below have since changed: the `monitor_kill_all` tool is
> now `monitor_kill` with `id: "*"`, and `heartbeatMinutes`/`timeoutSeconds` are no
> longer tool parameters (timeout stays available as `/monitor --timeout N`).

## Goal

Keep `pi-process-monitor`'s spawn, poll, file-tail, matched-event, and model-triggering heartbeat features while making session shutdown and watcher limits safe. This fork replaces, rather than co-loads with, `pi-process-monitor@1.2.0`.

## User-visible behavior

1. Keep the existing tools and commands: `monitor`, `monitor_status`, `monitor_kill`, `/monitor`, `/monitors`, and `/monitor-kill`.
2. Add `monitor_kill_all` and `/monitor-kill-all`.
   - Stop every active watcher atomically before reporting.
   - `/monitor-kill-all` emits one UI notification for every stopped watcher when `ctx.hasUI` is true.
   - It also appends one consolidated custom message with `pi.sendMessage` so the list participates in model context. It does not trigger a model turn merely because the user ran the slash command.
   - `monitor_kill_all` returns the same consolidated list in its tool result rather than adding a duplicate custom message.
   - With no active watchers, report that fact without appending a model-context message.
3. Never persist executable watcher definitions and never restore watchers in `session_start`.
4. During `session_shutdown`, invoke the same stop-all core, then synchronously persist one consolidated model-visible custom message listing all monitors stopped. The text names the shutdown reason (`quit`, `reload`, `new`, `resume`, or `fork`); for example, reload says that reload stopped the monitors and they must be restarted manually. On idle shutdown use `pi.sendMessage` without `triggerTurn`; if shutdown occurs while an agent is streaming, append a custom-message entry directly through the bound `SessionManager` so it cannot be stranded in Pi's steer queue. Shutdown must not wake the model. A later resume of the old session therefore has explicit context that the watchers no longer exist. On `session_start` with `reason === "fork"`, append a no-turn context note that source-session monitors were not carried into the fork, because Pi creates the fork before shutting down the source session. Other `session_start` reasons never scan or restore historical watchers.
5. Enforce at most 16 active watchers inside the shared synchronous `launch()` path so tools and commands cannot bypass it and concurrent tool launches reserve slots deterministically. Map membership is the single definition of active: stopped and naturally exited watchers are removed. `launch()` must contain no `await` between checking `watchers.size` and inserting the new watcher. Starting watcher 17 is rejected before any process/timer/file watcher is created. The tool path throws an error so Pi marks the result `isError`; its message says `16 active monitors; use monitor_status, then monitor_kill (or monitor_kill_all) before starting another.` The slash command catches the same typed limit error and shows it as a UI warning.
6. Preserve model-triggering heartbeats requested through `heartbeatMinutes`.
   - Heartbeats remain off unless requested.
   - One extension-level scheduler ticks every 30 seconds. Each watcher has its own `nextHeartbeatAt`; all active watchers due on a tick are included in one `monitor-heartbeat` custom message with `details: { watcherIds: string[] }` and `triggerTurn: true`, then each due time advances by its own interval.
   - A real matched/exit event since a watcher's preceding interval substitutes for that heartbeat. Heartbeats do not update `lastEventAt` or `eventCount`, so they cannot suppress subsequent heartbeats or make status claim a real event occurred.
   - Killing, timing out, or shutting down a watcher removes it from heartbeat scheduling.

## Lifecycle and concurrency design

1. A watcher owns all of its resources: child processes, poll interval, file watcher, backstop interval, timeout, coalescer timer/buffer, and heartbeat registration.
2. `stopWatcher` is synchronous and idempotent. It first marks `killed=true` and `alive=false`, then cancels timers/watchers, clears buffered output, and terminates in-flight child process groups. Spawn and poll children use `detached: true` on Unix; teardown signals the negative PID with SIGTERM and a bounded SIGKILL escalation, falling back to direct-child signaling where process groups are unavailable. Exception: `session_shutdown` with reason `quit` follows SIGTERM with an immediate SIGKILL, because the Pi process exits before any escalation timer could fire. No cleanup callback may emit.
3. Every event, coalescer flush, child callback, file callback, timeout callback, and heartbeat callback checks that the watcher is still active before sending a message.
4. Poll mode tracks and terminates in-flight polls. It assembles complete lines across chunks, bounds retained output, and compares complete line sets with the previous poll to avoid replaying identical old log lines every tick.
5. Spawn mode emits a process-exit event only for natural exits. User kill, kill-all, timeout cleanup, and shutdown do not generate a second process-exit turn.
6. Stopped watchers are removed from the active map after teardown. Natural spawn exits also release their slots. Status and limit checks operate on active watchers only; a killed spawn releases its slot immediately rather than waiting up to three seconds for SIGKILL.
7. Heartbeats use one extension-level scheduler/aggregation path, not one independent turn-producing timer per watcher.
8. All externally emitted monitor content remains tail-truncated to bounded lines and bytes.

## Context semantics

Use custom messages for monitor events and stop-all summaries because they participate in LLM context. Use `triggerTurn: true` only for matched events, natural process exits, timeouts, and requested heartbeat aggregates. Use `triggerTurn: false` for slash-command and shutdown cleanup summaries.

Shutdown persistence is the normal reopen-context mechanism. It writes directly as a custom-message entry when streaming so a queued steer cannot be lost. `session_start` never scans historical activity or restores anything; its only injection is the explicit fork note described above. A hard process crash cannot reliably append a shutdown summary, but no watcher can restart because watcher definitions are never persisted. `/reload` intentionally stops all monitors and records that fact; monitors must be recreated after reload.

## Packaging and migration

1. Create a local package under `~/.pi/agent/local/pi-process-monitor-safe` with its own package manifest, extension, updated skill/prompt documentation, tests, and upstream MIT license/attribution.
2. Keep the upstream npm package absent from global settings and add only the local package path.
3. Do not edit the active historical session JSONL. Its stale `monitor-watcher` entries are inert because this fork ignores them.
4. Document that loading the upstream package alongside the fork is unsupported because tool/command names would collide.

## Validation

1. Typecheck the extension.
2. Structure the runtime with injected clock/timer, spawn/process-group-kill, and filesystem adapters. Tests instantiate the extension/runtime with a mock `ExtensionAPI`, capture registered tools/commands and `sendMessage` options, use fake timers, and record group-kill calls. Keep one real-child integration smoke test.
3. Unit-test:
   - the 16th tool/command monitor starts, the 17th is refused through both paths, the tool refusal is an error with actionable text, and slots release immediately after stop or natural exit;
   - kill-all idempotence, empty behavior, `ctx.hasUI` guards, per-watcher UI notifications, and exactly one consolidated model-context report from the slash command;
   - no `appendEntry` persistence calls, no restore or startup note on `session_start`, and legacy `monitor-watcher` entries are ignored;
   - idle and mid-stream shutdown stop all modes and synchronously persist exactly one reason-aware custom-message summary without triggering a turn; fork startup receives exactly one source-monitor note, while ordinary startup/resume does not inject notes;
   - suppression of queued/coalesced messages and killed-process exit messages after stop;
   - in-flight poll process-group termination;
   - heartbeat aggregation, `triggerTurn: true`, real-event suppression, and cancellation;
   - natural exit versus killed exit behavior;
   - timeout cleanup;
   - repeated reload/resume does not create watchers;
   - print/RPC contexts without UI do not crash.
4. Run an isolated Pi load smoke test with the local extension/package.
5. Verify global settings contain the local fork and not `npm:pi-process-monitor`.
