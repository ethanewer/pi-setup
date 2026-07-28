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
 *   child process groups (SIGTERM with a bounded SIGKILL escalation).
 * - Every asynchronous callback re-checks that its watcher is still active
 *   before emitting, so no message can escape after a kill or shutdown.
 * - Heartbeats are aggregated by one extension-level scheduler that ticks
 *   every 30 seconds and emits a single turn-triggering message listing all
 *   due watchers; a real event within a watcher's preceding interval
 *   substitutes for that heartbeat.
 * - Nothing is ever persisted: watcher definitions never reach the session
 *   file, so nothing can be restored (or leak) across restarts.
 */

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
  MAX_POLL_RETAINED_BYTES,
  MAX_SUMMARY_LINES,
  MESSAGE_TYPE_EVENT,
  MESSAGE_TYPE_HEARTBEAT,
  MIN_POLL_INTERVAL_SECONDS,
  type MonitorMode,
  type MonitorRuntime,
  MonitorLimitError,
  type RuntimeDeps,
  SIGKILL_ESCALATION_MS,
  type TimerHandle,
  type WatcherMeta,
} from "./types.ts";
import { tailBytes, truncateTail } from "./text.ts";

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
   * Release a watcher whose work ended naturally (process exit, spawn
   * failure). `killed` stays false so callers can distinguish the paths.
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
  function stopWatcher(w: WatcherState): boolean {
    if (watchers.get(w.id) !== w) return false;
    w.killed = true;
    w.alive = false;
    watchers.delete(w.id);
    runCleanups(w);
    for (const child of [...w.children]) terminateChild(child);
    maybeStopHeartbeatScheduler();
    return true;
  }

  function terminateChild(child: ChildRef): void {
    if (child.exited) return;
    signalChild(child, "SIGTERM");
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
    handle.onExit(() => {
      child.exited = true;
      if (child.killTimer !== null) {
        clock.clearTimeout(child.killTimer);
        child.killTimer = null;
      }
      w.children.delete(child);
    });
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
      const { content } = truncateTail(buf.join("\n"), {
        maxLines,
        maxBytes: MAX_EMIT_BYTES,
      });
      buf = [];
      emit(w, content);
    };
    return {
      push(line: string): void {
        if (!isActive(w)) return;
        buf.push(line);
        if (timer !== null) clock.clearTimeout(timer);
        timer = clock.setTimeout(flush, coalesceMs);
      },
      flushNow: flush,
      clear(): void {
        buf = [];
        if (timer !== null) {
          clock.clearTimeout(timer);
          timer = null;
        }
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
    let handle: ChildHandle;
    try {
      handle = proc.spawn(command, cwd);
    } catch (error) {
      emit(w, `FAILED TO SPAWN: ${(error as Error).message}`);
      releaseWatcher(w);
      return;
    }
    trackChild(w, handle);
    let pending = "";
    const onChunk = (chunk: string): void => {
      if (!isActive(w)) return;
      pending += chunk;
      const lines = pending.split("\n");
      pending = lines.pop() ?? "";
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
    const tick = (): void => {
      if (!isActive(w)) return;
      let handle: ChildHandle;
      try {
        handle = proc.spawn(command, cwd);
      } catch (error) {
        emit(w, `POLL SPAWN ERROR: ${(error as Error).message}`);
        return; // next tick retries
      }
      trackChild(w, handle);
      let out = "";
      const capture = (chunk: string): void => {
        out = tailBytes(out + chunk, MAX_POLL_RETAINED_BYTES);
      };
      handle.onStdout(capture);
      handle.onStderr(capture);
      handle.onError((error) => {
        if (isActive(w)) emit(w, `POLL ERROR: ${error.message}`);
      });
      handle.onExit(() => {
        if (!isActive(w)) return;
        // Compare complete-line sets against the previous poll so identical
        // old log lines are not replayed every tick.
        const current = new Set(
          out.split("\n").map((l) => l.trim()).filter(Boolean),
        );
        for (const line of current) {
          if (!prevLines.has(line) && matcher(line)) push(line);
        }
        prevLines = current;
      });
    };
    tick();
    const interval = clock.setInterval(
      tick,
      Math.max(MIN_POLL_INTERVAL_SECONDS, intervalSec) * 1000,
    );
    w.cleanups.push(() => clock.clearInterval(interval));
  }

  // ---- file: tail appended lines ---------------------------------------
  function startFile(
    w: WatcherState,
    logFile: string,
    matcher: (line: string) => boolean,
    push: (line: string) => void,
  ): void {
    let size = files.statSize(logFile) ?? 0;
    const readNew = (): void => {
      if (!isActive(w)) return;
      const current = files.statSize(logFile);
      if (current === null) return; // may appear later
      if (current < size) size = 0; // truncated/rotated
      if (current === size) return;
      let text: string;
      try {
        text = files.readSlice(logFile, size, current);
      } catch {
        return; // transient read failure; backstop retries
      }
      size = current;
      for (const line of text.split("\n")) {
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
    const coalesceMs = Math.max(0, opts.coalesceSeconds ?? DEFAULT_COALESCE_SECONDS) * 1000;
    const maxLines = opts.maxLines ?? DEFAULT_MAX_LINES;
    const matcher = compileMatchers(opts.notifyOn);
    const watchingFor =
      (opts.notifyOn && opts.notifyOn.length
        ? opts.notifyOn.join(" | ")
        : "milestones/failures (default)") + (mode === "spawn" ? " + exit" : "");

    const w: WatcherState = {
      id: deps.randomId(),
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
    };
    watchers.set(w.id, w);

    try {
      const coalescer = makeCoalescer(w, coalesceMs, maxLines);
      w.coalescer = coalescer;
      w.cleanups.push(() => coalescer.clear());
      const push = (line: string): void => coalescer.push(line);

      if (opts.heartbeatMinutes && opts.heartbeatMinutes > 0) {
        const intervalMs = Math.max(1, opts.heartbeatMinutes) * 60_000;
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
      else startFile(w, logFile!, matcher, push);
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
    stopAll: () => {
      const stopped: WatcherMeta[] = [];
      for (const w of [...watchers.values()]) {
        if (stopWatcher(w)) stopped.push(toMeta(w));
      }
      return stopped;
    },
    activeCount: () => watchers.size,
    heartbeatSchedulerActive: () => heartbeatTimer !== null,
  };
}
