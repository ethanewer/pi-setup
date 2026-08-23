/**
 * Core watcher runtime for pi-process-monitor-safe.
 *
 * Forked from pi-process-monitor@1.2.0 (MIT, Francesco Frapporti) with the
 * lifecycle hardened per PLAN.md:
 *
 * - Map membership is the single definition of "active". Stopped and
 *   naturally exited watchers are removed immediately, releasing their slot.
 * - `launch()` is fully synchronous; the 16-watcher cap check and the slot
 *   reservation have no await between them, and watcher 17 is refused before
 *   any process, timer, or file watcher is created.
 * - `stopWatcher()` is synchronous and idempotent: it flags the watcher dead,
 *   cancels every timer/watcher/buffer it owns, then terminates in-flight
 *   child process groups (SIGTERM with a bounded SIGKILL escalation; `quit`
 *   shutdown uses an immediate SIGKILL because Pi exits before any timer).
 * - Every asynchronous callback re-checks that its watcher is still active
 *   before emitting, so no message can escape after a kill or shutdown.
 * - Heartbeats are aggregated by one extension-level scheduler that ticks
 *   every 30 seconds and emits a single turn-triggering message listing all
 *   due watchers; a real event within a watcher's preceding interval
 *   substitutes for that heartbeat.
 * - Nothing is ever persisted: watcher definitions never reach the session
 *   file, so nothing can be restored (or leak) across restarts.
 */

import path from "node:path";
import {
  type ChildHandle,
  type Clock,
  DEFAULT_COALESCE_SECONDS,
  DEFAULT_MAX_LINES,
  FILE_BACKSTOP_MS,
  FILE_DEBOUNCE_MS,
  HEARTBEAT_TICK_MS,
  type LaunchOptions,
  MAX_ACTIVE_WATCHERS,
  MAX_EMIT_BYTES,
  MAX_FILE_PENDING_BYTES,
  MAX_FILE_READ_BYTES,
  MAX_POLL_RETAINED_BYTES,
  MAX_SPAWN_PENDING_BYTES,
  MAX_SUMMARY_LINES,
  MESSAGE_TYPE_EVENT,
  MESSAGE_TYPE_HEARTBEAT,
  MIN_POLL_INTERVAL_SECONDS,
  type MonitorMode,
  type MonitorRuntime,
  MonitorLimitError,
  type RuntimeDeps,
  SIGKILL_ESCALATION_MS,
  type StopAllOptions,
  type TimerHandle,
  type WatcherMeta,
} from "./types.ts";

import { boundPartialLine, tailBytes, truncateTail } from "./text.ts";

/**
 * Hard ceiling on coalescing, as a multiple of coalesceMs. Output that keeps matching
 * faster than the debounce window would otherwise postpone the ping indefinitely — a
 * steadily-matching watcher never fired at all.
 */
const MAX_COALESCE_MULTIPLE = 4;

// Lines surfaced by default (case-insensitive regex). Override per-call via notifyOn.
export const DEFAULT_NOTIFY = [
  "error", "fail", "failed", "oom", "out of memory", "killed", "traceback",
  "exception", "fatal", "abort", "panic", "segfault",
  "saved", "checkpoint", "complete", "completed", "done", "finished",
  "ready", "started", "listening", "success", "\\bok\\b", "✓", "✔",
];

interface ChildRef {
  handle: ChildHandle;
  pid: number | undefined;
  exited: boolean;
  killTimer: TimerHandle | null;
}

interface Coalescer {
  push(line: string): void;
  /** Emit any buffered lines immediately (used before a natural exit event). */
  flushNow(): void;
  /** Drop buffered lines and cancel the pending flush timer. */
  clear(): void;
}

interface WatcherState {
  id: string;
  label: string;
  mode: MonitorMode;
  watchingFor: string;
  startedAt: number;
  /** Timestamp of the last REAL event (matched lines, exit, timeout, errors). */
  lastEventAt: number | null;
  eventCount: number;
  alive: boolean;
  killed: boolean;
  heartbeat: { intervalMs: number; nextAt: number } | null;
  /** Cancels timers, file watchers, and buffered output. Never emits. */
  cleanups: Array<() => void>;
  /** In-flight children (the spawn child, or currently running poll ticks). */
  children: Set<ChildRef>;
  coalescer: Coalescer | null;
  /** Set once the no-line-break warning has fired, so it never fires twice. */
  partialLineWarned: boolean;
}

export function compileMatchers(notifyOn?: string[]): (line: string) => boolean {
  const pats = (notifyOn && notifyOn.length ? notifyOn : DEFAULT_NOTIFY).map((p) => {
    try {
      return new RegExp(p, "i");
    } catch {
      return new RegExp(p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
    }
  });
  return (line: string) => pats.some((r) => r.test(line));
}

export function createMonitorRuntime(deps: RuntimeDeps): MonitorRuntime {
  const { clock, proc, files, send } = deps;
  const watchers = new Map<string, WatcherState>();
  let heartbeatTimer: TimerHandle | null = null;

  const isActive = (w: WatcherState): boolean =>
    watchers.get(w.id) === w && w.alive && !w.killed;

  const labelTag = (w: Pick<WatcherState, "id" | "label">): string =>
    `${w.id}${w.label ? " · " + w.label : ""}`;

  const iso = (ms: number | null): string | null =>
    ms === null ? null : new Date(ms).toISOString();

  const toMeta = (w: WatcherState): WatcherMeta => ({
    id: w.id,
    label: w.label,
    mode: w.mode,
    watchingFor: w.watchingFor,
    startedAt: new Date(w.startedAt).toISOString(),
    lastEventAt: iso(w.lastEventAt),
    eventCount: w.eventCount,
    alive: w.alive,
  });

  /** Emit one real watcher event. Counts toward heartbeat substitution. */
  function emit(w: WatcherState, body: string): void {
    if (!isActive(w)) return;
    w.lastEventAt = clock.now();
    w.eventCount++;
    send(
      {
        customType: MESSAGE_TYPE_EVENT,
        content: `[watcher ${labelTag(w)}] ${body}`,
        display: true,
        details: { id: w.id },
      },
      { triggerTurn: true, deliverAs: "steer" },
    );
  }

  /**
   * Bound an unterminated partial line, and say so the first time it happens.
   *
   * Matching is line-oriented, so a process that only rewrites one line with carriage
   * returns can never match anything: the watcher looks like it is waiting patiently when
   * it is actually blind. That ambiguity is the real damage — it is indistinguishable from
   * a job that simply has not reached its marker yet, and an agent will wait on it forever.
   *
   * Splitting on \r instead would make such output match, but a progress bar redrawing ten
   * times a second would then reach the coalescer's hard flush every 8s, waking the agent
   * ~450 times an hour for the life of the run. One warning is the cheaper signal, and it
   * leaves matching semantics untouched for every watcher that already works.
   */
  function boundPending(w: WatcherState, pending: string, maxBytes: number): string {
    if (Buffer.byteLength(pending, "utf8") <= maxBytes) return pending;
    if (!w.partialLineWarned) {
      w.partialLineWarned = true;
      emit(
        w,
        `NO LINE BREAK in ${maxBytes} bytes of output. This watcher matches whole lines, so ` +
          `output that redraws one line with carriage returns (a progress bar) can never match ` +
          `any pattern. Have the job print newline-terminated markers, or watch it with poll mode.`,
      );
    }
    return boundPartialLine(pending, maxBytes);
  }

  function runCleanups(w: WatcherState): void {
    const cleanups = w.cleanups;
    w.cleanups = [];
    for (const cleanup of cleanups) {
      try {
        cleanup();
      } catch {
        /* teardown must never throw */
      }
    }
  }

  /**
   * Release a watcher whose work ended naturally (process exit, async spawn
   * error). `killed` stays false so callers can distinguish the paths.
   */
  function releaseWatcher(w: WatcherState): void {
    if (watchers.get(w.id) === w) watchers.delete(w.id);
    w.alive = false;
    runCleanups(w);
    maybeStopHeartbeatScheduler();
  }

  /**
   * Forcibly stop a watcher. Synchronous and idempotent; frees the slot
   * immediately rather than waiting for SIGKILL escalation.
   */
  function stopWatcher(w: WatcherState, immediateKill = false): boolean {
    if (watchers.get(w.id) !== w) return false;
    w.killed = true;
    w.alive = false;
    watchers.delete(w.id);
    runCleanups(w);
    for (const child of [...w.children]) terminateChild(child, immediateKill);
    maybeStopHeartbeatScheduler();
    return true;
  }

  function terminateChild(child: ChildRef, immediateKill: boolean): void {
    if (child.exited) return;
    signalChild(child, "SIGTERM");
    if (immediateKill) {
      // `quit` shutdown: Pi's process exits before an escalation timer could
      // ever fire, so follow up with SIGKILL right away.
      if (!child.exited) signalChild(child, "SIGKILL");
      return;
    }
    child.killTimer = clock.setTimeout(() => {
      child.killTimer = null;
      if (!child.exited) signalChild(child, "SIGKILL");
    }, SIGKILL_ESCALATION_MS);
  }

  function signalChild(child: ChildRef, signal: "SIGTERM" | "SIGKILL"): void {
    const grouped = child.pid !== undefined && proc.killGroup(child.pid, signal);
    if (!grouped) {
      try {
        child.handle.kill(signal);
      } catch {
        /* already gone */
      }
    }
  }

  /** Register a child and wire the shared exited/kill-timer bookkeeping. */
  function trackChild(w: WatcherState, handle: ChildHandle): ChildRef {
    const child: ChildRef = { handle, pid: handle.pid, exited: false, killTimer: null };
    w.children.add(child);
    const untrack = (): void => {
      child.exited = true;
      if (child.killTimer !== null) {
        clock.clearTimeout(child.killTimer);
        child.killTimer = null;
      }
      w.children.delete(child);
    };
    handle.onExit(untrack);
    // A child that errors may never reach exit; untrack it here too so failed
    // handles cannot accumulate in `w.children`.
    handle.onError(untrack);
    return child;
  }

  function makeCoalescer(w: WatcherState, coalesceMs: number, maxLines: number): Coalescer {
    let buf: string[] = [];
    let timer: TimerHandle | null = null;
    const flush = (): void => {
      if (timer !== null) {
        clock.clearTimeout(timer);
        timer = null;
      }
      if (!buf.length) return;
      if (!isActive(w)) {
        buf = [];
        return;
      }
      if (buf.length === 0) return;
      const { content } = truncateTail(buf.join("\n"), {
        maxLines,
        maxBytes: MAX_EMIT_BYTES,
      });
      buf = [];
      emit(w, content);
    };
    // A pure debounce starves: a process that matches at a steady interval shorter than
    // coalesceMs pushes the deadline forward on every line and the watcher never pings at
    // all. The first buffered line therefore also starts a hard deadline that a later line
    // cannot move.
    let deadline: ReturnType<Clock["setTimeout"]> | null = null;
    const clearTimers = () => {
      if (timer !== null) {
        clock.clearTimeout(timer);
        timer = null;
      }
      if (deadline !== null) {
        clock.clearTimeout(deadline);
        deadline = null;
      }
    };
    const flushAndClear = () => {
      clearTimers();
      flush();
    };
    return {
      push(line: string): void {
        if (!isActive(w)) return;
        buf.push(line);
        if (timer !== null) clock.clearTimeout(timer);
        timer = clock.setTimeout(flushAndClear, coalesceMs);
        if (deadline === null) deadline = clock.setTimeout(flushAndClear, coalesceMs * MAX_COALESCE_MULTIPLE);
      },
      flushNow: flushAndClear,
      clear(): void {
        buf = [];
        clearTimers();
      },
    };
  }

  // ---- spawn: run once, tail until exit --------------------------------
  function startSpawn(
    w: WatcherState,
    command: string,
    cwd: string,
    matcher: (line: string) => boolean,
    push: (line: string) => void,
  ): void {
    // A synchronous spawn failure propagates to launch(), which tears the
    // reserved slot down and rethrows — a watcher that never started must
    // surface as a failed launch, not as a running watcher.
    const handle = proc.spawn(command, cwd);
    trackChild(w, handle);
    let pending = "";
    const onChunk = (chunk: string): void => {
      if (!isActive(w)) return;
      pending += chunk;
      const lines = pending.split("\n");
      pending = boundPending(w, lines.pop() ?? "", MAX_SPAWN_PENDING_BYTES);
      for (const line of lines) {
        if (line.trim() && matcher(line)) push(line);
      }
    };
    handle.onStdout(onChunk);
    handle.onStderr(onChunk);
    handle.onError((error) => {
      if (!isActive(w)) return;
      emit(w, `SPAWN ERROR: ${error.message}`);
      releaseWatcher(w);
    });
    handle.onExit((code, signal) => {
      // trackChild already flagged the child as exited and cleared timers.
      if (!isActive(w)) return; // killed/timeout/shutdown: stay silent
      if (pending.trim() && matcher(pending)) push(pending);
      pending = "";
      w.coalescer?.flushNow();
      emit(w, `PROCESS EXITED (code=${code} signal=${signal ?? "none"})`);
      releaseWatcher(w);
    });
  }

  // ---- poll: re-run a command on an interval (SSH/remote) --------------
  function startPoll(
    w: WatcherState,
    command: string,
    cwd: string,
    intervalSec: number,
    matcher: (line: string) => boolean,
    push: (line: string) => void,
  ): void {
    let prevLines = new Set<string>();
    // Persistent failures (SSH box down, command gone) emit exactly one event
    // for the first consecutive failure; repeats stay silent until a poll
    // completes successfully again, which re-arms the latch.
    let errorLatched = false;
    // Poll ticks never overlap: while a tick's child is still running (slow
    // SSH, hung remote), subsequent ticks are skipped rather than piling up
    // concurrent children whose diffs would interleave.
    let inFlight = false;
    const reportFailure = (body: string): void => {
      if (errorLatched || !isActive(w)) return;
      errorLatched = true;
      emit(w, `${body} — suppressing repeats until a poll succeeds; retrying every tick`);
    };
    const intervalMs = Math.max(MIN_POLL_INTERVAL_SECONDS, intervalSec) * 1000;
    // A tick that never exits used to end the watcher permanently: `inFlight` stayed
    // latched, every later tick returned early, and nothing was emitted again. A hung SSH
    // is the ordinary way that happens, and poll mode exists to watch remote hosts, so the
    // failure was both reachable and silent. Ported from upstream 2.0.0's poll timeout.
    // Kept strictly under the interval so a killed tick cannot collide with its successor.
    const tickTimeoutMs = Math.max(250, intervalMs - 1000);
    // One handle for the whole watcher: a tick either clears its timer or the timer has
    // already fired, so at most one is ever live. Registering the cleanup per tick instead
    // would grow w.cleanups once per tick for the life of a multi-day watcher.
    let tickTimer: TimerHandle | null = null;
    const clearTickTimer = (): void => {
      if (tickTimer === null) return;
      clock.clearTimeout(tickTimer);
      tickTimer = null;
    };
    // A timed-out child is abandoned, not awaited: it may still deliver an exit or an error
    // minutes later, after the next tick already owns `inFlight` and `tickTimer`. Without
    // this token that late callback cleared the *replacement* tick's timeout and released
    // its slot — reinstating the very hang it was added to prevent, and letting two children
    // run at once. Only the current tick may touch shared state.
    let generation = 0;
    const tick = (): void => {
      if (!isActive(w) || inFlight) return;
      let handle: ChildHandle;
      try {
        handle = proc.spawn(command, cwd);
      } catch (error) {
        reportFailure(`POLL SPAWN ERROR: ${(error as Error).message}`);
        return; // next tick retries
      }
      const child = trackChild(w, handle);
      const myGeneration = ++generation;
      const isCurrentTick = (): boolean => myGeneration === generation;
      inFlight = true;
      let out = "";
      // Bounded retention truncates from the head, which can leave the first
      // retained line partial; flag it so it is dropped before matching/dedup.
      let headTruncated = false;
      let failed = false;

      tickTimer = clock.setTimeout(() => {
        if (!isCurrentTick()) return;
        tickTimer = null;
        if (child.exited) return;
        // Release the slot before killing. The child may never deliver an exit at all, and
        // the next tick must not inherit this one's latch — that is the whole bug.
        inFlight = false;
        failed = true;
        terminateChild(child, false);
        reportFailure(`POLL TIMEOUT after ${Math.round(tickTimeoutMs / 1000)}s; stopped that tick`);
      }, tickTimeoutMs);
      const capture = (chunk: string): void => {
        const combined = out + chunk;
        out = tailBytes(combined, MAX_POLL_RETAINED_BYTES);
        if (out.length < combined.length) headTruncated = true;
      };
      handle.onStdout(capture);
      handle.onStderr(capture);
      handle.onError((error) => {
        if (!isCurrentTick()) return; // abandoned tick: its slot and timer belong to another
        clearTickTimer();
        if (failed) return; // already reported as a timeout
        failed = true;
        reportFailure(`POLL ERROR: ${error.message}`);
      });
      handle.onExit(() => {
        if (!isCurrentTick()) return; // ditto: a late exit must not release someone else's slot
        clearTickTimer();
        inFlight = false;
        if (failed || !isActive(w)) return; // an errored poll neither diffs nor re-arms
        errorLatched = false;
        // Compare complete-line sets against the previous poll so identical
        // old log lines are not replayed every tick.
        const lines = out.split("\n");
        if (headTruncated) lines.shift(); // potentially partial: never match or dedup on it
        const current = new Set(lines.map((l) => l.trim()).filter(Boolean));
        for (const line of current) {
          if (!prevLines.has(line) && matcher(line)) push(line);
        }
        prevLines = current;
      });
    };
    tick();
    const interval = clock.setInterval(tick, intervalMs);
    // Teardown cancels both, or a stopped watcher could still emit from a pending timer.
    w.cleanups.push(() => {
      clock.clearInterval(interval);
      clearTickTimer();
    });
  }

  // ---- file: tail appended lines ---------------------------------------
  function startFile(
    w: WatcherState,
    logFile: string,
    matcher: (line: string) => boolean,
    push: (line: string) => void,
  ): void {
    let size = files.statSize(logFile) ?? 0;
    // Unterminated trailing data is held (bounded) until its newline arrives,
    // so a line flushed to disk in two writes is matched once, assembled.
    let pending = "";
    const readNew = (): void => {
      if (!isActive(w)) return;
      const current = files.statSize(logFile);
      if (current === null) return; // may appear later
      if (current < size) {
        size = 0; // truncated/rotated: the old partial line is gone
        pending = "";
      }
      if (current === size) return;
      if (current - size > MAX_FILE_READ_BYTES) {
        // Bound per-read allocation: skip ahead and keep only the tail of a
        // huge burst (mirrors poll mode's bounded retention).
        size = current - MAX_FILE_READ_BYTES;
        pending = "";
      }
      let text: string;
      try {
        text = files.readSlice(logFile, size, current);
      } catch {
        return; // transient read failure; backstop retries
      }
      size = current;
      const parts = (pending + text).split("\n");
      // File mode was already bounded, but it is just as blind to a carriage-return-only
      // log, so it gets the same one-time warning.
      pending = boundPending(w, parts.pop() ?? "", MAX_FILE_PENDING_BYTES);
      for (const line of parts) {
        if (line.trim() && matcher(line)) push(line);
      }
    };
    let debounce: TimerHandle | null = null;
    const closeWatch = files.watch(logFile, () => {
      if (!isActive(w)) return;
      if (debounce !== null) clock.clearTimeout(debounce);
      debounce = clock.setTimeout(() => {
        debounce = null;
        readNew();
      }, FILE_DEBOUNCE_MS);
    });
    const backstop = clock.setInterval(readNew, FILE_BACKSTOP_MS);
    w.cleanups.push(() => {
      clock.clearInterval(backstop);
      if (debounce !== null) {
        clock.clearTimeout(debounce);
        debounce = null;
      }
      closeWatch?.();
    });
  }

  // ---- heartbeats: one extension-level scheduler ------------------------
  function ensureHeartbeatScheduler(): void {
    if (heartbeatTimer === null) {
      heartbeatTimer = clock.setInterval(heartbeatTick, HEARTBEAT_TICK_MS);
    }
  }

  function maybeStopHeartbeatScheduler(): void {
    if (heartbeatTimer === null) return;
    for (const w of watchers.values()) {
      if (w.heartbeat) return;
    }
    clock.clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }

  function heartbeatTick(): void {
    const now = clock.now();
    const due: WatcherState[] = [];
    for (const w of watchers.values()) {
      const hb = w.heartbeat;
      if (!hb || !w.alive || w.killed) continue;
      if (now < hb.nextAt) continue;
      // A real event since this watcher's preceding interval substitutes
      // for the heartbeat, but the due time still advances.
      const windowStart = hb.nextAt - hb.intervalMs;
      const hadRealEvent = w.lastEventAt !== null && w.lastEventAt >= windowStart;
      while (hb.nextAt <= now) hb.nextAt += hb.intervalMs;
      if (!hadRealEvent) due.push(w);
    }
    if (!due.length) return;
    const lines = due.map(
      (w) =>
        `- ${labelTag(w)} [${w.mode}] still running · events=${w.eventCount} · last=${iso(w.lastEventAt) ?? "never"}`,
    );
    const { content } = truncateTail(
      `[monitor heartbeat] ${due.length} watcher(s) still running:\n${lines.join("\n")}`,
      { maxLines: MAX_SUMMARY_LINES, maxBytes: MAX_EMIT_BYTES },
    );
    // Heartbeats intentionally do NOT update lastEventAt/eventCount, so they
    // can never suppress later heartbeats or masquerade as real events.
    send(
      {
        customType: MESSAGE_TYPE_HEARTBEAT,
        content,
        display: true,
        details: { watcherIds: due.map((w) => w.id) },
      },
      { triggerTurn: true, deliverAs: "steer" },
    );
  }

  // ---- launch ------------------------------------------------------------
  function launch(opts: LaunchOptions): WatcherMeta {
    const command = opts.command?.trim() ? opts.command : undefined;
    const logFile = opts.logFile?.trim() ? opts.logFile : undefined;
    if (!command && !logFile) {
      throw new Error("monitor: provide `command` and/or `logFile`.");
    }
    // Limit check + slot reservation are back-to-back synchronous statements
    // (no await anywhere in launch), so concurrent launches cannot pass the
    // check together, and watcher 17 is refused before any resource exists.
    if (watchers.size >= MAX_ACTIVE_WATCHERS) {
      throw new MonitorLimitError(MAX_ACTIVE_WATCHERS);
    }

    const mode: MonitorMode = logFile ? "file" : opts.intervalSeconds ? "poll" : "spawn";
    const cwd = opts.cwd ?? deps.defaultCwd();
    // Resolve relative logFile against the watcher cwd (session cwd), matching how
    // the model saw paths; otherwise it silently tails the extension process cwd.
    const watchFile = logFile && !path.isAbsolute(logFile) ? path.join(cwd, logFile) : logFile;
    const coalesceMs = Math.max(0, opts.coalesceSeconds ?? DEFAULT_COALESCE_SECONDS) * 1000;
    const maxLines = opts.maxLines ?? DEFAULT_MAX_LINES;
    const matcher = compileMatchers(opts.notifyOn);
    const watchingFor =
      (opts.notifyOn && opts.notifyOn.length
        ? opts.notifyOn.join(" | ")
        : "milestones/failures (default)") + (mode === "spawn" ? " + exit" : "");

    // Guard against random-id collisions: a duplicate key would silently
    // orphan the incumbent watcher's map slot. Retry, then force uniqueness.
    let id = deps.randomId();
    for (let attempt = 0; watchers.has(id) && attempt < 8; attempt++) id = deps.randomId();
    const base = id;
    for (let n = 2; watchers.has(id); n++) id = `${base}-${n}`;

    const w: WatcherState = {
      id,
      label: opts.label ?? "",
      mode,
      watchingFor,
      startedAt: clock.now(),
      lastEventAt: null,
      eventCount: 0,
      alive: true,
      killed: false,
      heartbeat: null,
      cleanups: [],
      children: new Set(),
      coalescer: null,
      partialLineWarned: false,
    };
    watchers.set(w.id, w);

    try {
      const coalescer = makeCoalescer(w, coalesceMs, maxLines);
      w.coalescer = coalescer;
      w.cleanups.push(() => coalescer.clear());
      const push = (line: string): void => coalescer.push(line);

      if (opts.heartbeatMinutes && opts.heartbeatMinutes > 0) {
        // Floor at 0.5 min: the scheduler ticks every 30s, so anything finer
        // could not be honored anyway.
        const intervalMs = Math.max(0.5, opts.heartbeatMinutes) * 60_000;
        w.heartbeat = { intervalMs, nextAt: clock.now() + intervalMs };
        ensureHeartbeatScheduler();
      }

      if (opts.timeoutSeconds && opts.timeoutSeconds > 0) {
        const timeout = clock.setTimeout(() => {
          if (!isActive(w)) return;
          emit(w, `TIMEOUT after ${opts.timeoutSeconds}s — auto-stopping watcher`);
          stopWatcher(w);
        }, opts.timeoutSeconds * 1000);
        w.cleanups.push(() => clock.clearTimeout(timeout));
      }

      if (mode === "spawn") startSpawn(w, command!, cwd, matcher, push);
      else if (mode === "poll") startPoll(w, command!, cwd, opts.intervalSeconds!, matcher, push);
      else startFile(w, watchFile!, matcher, push);
    } catch (error) {
      stopWatcher(w);
      throw error;
    }
    return toMeta(w);
  }

  return {
    launch,
    list: () => [...watchers.values()].map(toMeta),
    get: (id) => {
      const w = watchers.get(id);
      return w ? toMeta(w) : undefined;
    },
    stop: (id) => {
      const w = watchers.get(id);
      if (!w) return undefined;
      stopWatcher(w);
      return toMeta(w);
    },
    stopAll: (options?: StopAllOptions) => {
      const stopped: WatcherMeta[] = [];
      for (const w of [...watchers.values()]) {
        if (stopWatcher(w, options?.immediateKill ?? false)) stopped.push(toMeta(w));
      }
      return stopped;
    },
    activeCount: () => watchers.size,
    heartbeatSchedulerActive: () => heartbeatTimer !== null,
  };
}
