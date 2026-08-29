/**
 * Shared types, constants, and injected-adapter interfaces for the
 * pi-process-monitor-safe runtime.
 *
 * The runtime never touches globals directly: clocks, process spawning,
 * process-group kills, and filesystem access all flow through the adapters
 * defined here so tests can drive every code path deterministically.
 */

/** Hard cap on simultaneously active watchers, enforced inside `launch()`. */
export const MAX_ACTIVE_WATCHERS = 16;

/** The single extension-level heartbeat scheduler ticks on this cadence. */
export const HEARTBEAT_TICK_MS = 30_000;

/** After SIGTERM, escalate to SIGKILL if the child has not exited by then. */
export const SIGKILL_ESCALATION_MS = 3_000;

/** Poll mode never runs faster than this. */
export const MIN_POLL_INTERVAL_SECONDS = 2;

/** File mode backstop poll cadence (fs.watch can miss events). */
export const FILE_BACKSTOP_MS = 5_000;

/** File mode change-event debounce window. */
export const FILE_DEBOUNCE_MS = 150;

/** Byte cap applied to every externally emitted monitor message. */
export const MAX_EMIT_BYTES = 8_000;

/** Line cap for aggregate (heartbeat / stop-all) messages. */
export const MAX_SUMMARY_LINES = 64;

/** Poll mode bounds retained per-tick output to this many bytes (tail-kept). */
export const MAX_POLL_RETAINED_BYTES = 256 * 1024;

/** File mode reads at most this many bytes per pass; larger bursts skip ahead to the tail. */
export const MAX_FILE_READ_BYTES = 256 * 1024;

/** File mode retains at most this many bytes of an unterminated partial line. */
export const MAX_FILE_PENDING_BYTES = 64 * 1024;

/**
 * Spawn mode retains at most this many bytes of an unterminated partial line.
 * Spawn had no bound at all: a process that only ever rewrites one line with carriage
 * returns produced no newline, so the buffer grew for the lifetime of the run.
 */
export const MAX_SPAWN_PENDING_BYTES = 64 * 1024;

export const DEFAULT_COALESCE_SECONDS = 2;
export const DEFAULT_MAX_LINES = 20;

/** Custom message types this extension emits into model context. */
export const MESSAGE_TYPE_EVENT = "monitor";
export const MESSAGE_TYPE_HEARTBEAT = "monitor-heartbeat";
export const MESSAGE_TYPE_STOP_ALL = "monitor-stop-all";
export const MESSAGE_TYPE_NOTE = "monitor-note";

/**
 * Legacy custom-entry type written by upstream pi-process-monitor. This fork
 * never writes it and never reads it back; the constant exists only so tests
 * can assert stale entries are ignored.
 */
export const LEGACY_WATCHER_ENTRY_TYPE = "monitor-watcher";

export type MonitorMode = "spawn" | "poll" | "file";
export type KillSignal = "SIGTERM" | "SIGKILL";

/** Opaque timer handle owned by the injected clock. */
export type TimerHandle = unknown;

/** Injected time source. All timers the runtime creates go through this. */
export interface Clock {
  now(): number;
  setTimeout(fn: () => void, ms: number): TimerHandle;
  clearTimeout(handle: TimerHandle): void;
  setInterval(fn: () => void, ms: number): TimerHandle;
  clearInterval(handle: TimerHandle): void;
}

/**
 * Handle over one spawned child. Multiple callbacks may be registered per
 * event. Adapters must invoke exit callbacks exactly once, only after the
 * child has fully finished — all stdio has been delivered (Node `close`, not
 * `exit`) or the child errored and will never produce more events.
 */
export interface ChildHandle {
  readonly pid: number | undefined;
  onStdout(cb: (chunk: string) => void): void;
  onStderr(cb: (chunk: string) => void): void;
  onExit(cb: (code: number | null, signal: string | null) => void): void;
  onError(cb: (error: Error) => void): void;
  /** Signal the direct child (fallback when group kill is unavailable). */
  kill(signal: KillSignal): void;
}

export interface ProcessAdapter {
  /** Spawn `command` through a shell. May throw synchronously. */
  spawn(command: string, cwd: string): ChildHandle;
  /**
   * Signal the process group rooted at `pid`. Returns false when process
   * groups are unavailable or the group is already gone, in which case the
   * caller falls back to direct-child signaling. On Windows this is
   * `taskkill /T` (forced for SIGKILL).
   */
  killGroup(pid: number, signal: KillSignal): boolean;
}

export interface FileAdapter {
  /** Size in bytes, or null when the file does not exist (yet). */
  statSize(path: string): number | null;
  /** Read bytes [start, end) decoded as UTF-8. May throw. */
  readSlice(path: string, start: number, end: number): string;
  /**
   * Watch for change events. Returns a close function, or null when watching
   * is unavailable (missing file); callers then rely on the backstop poll.
   */
  watch(path: string, onChange: () => void): (() => void) | null;
}

/** Custom message payload handed to the injected sink (pi.sendMessage). */
export interface MonitorCustomMessage {
  customType: string;
  content: string;
  display: boolean;
  details?: unknown;
}

export interface MonitorSendOptions {
  triggerTurn: boolean;
  deliverAs: "steer";
}

export type MessageSink = (
  message: MonitorCustomMessage,
  options: MonitorSendOptions,
) => void;

export interface RuntimeDeps {
  clock: Clock;
  proc: ProcessAdapter;
  files: FileAdapter;
  send: MessageSink;
  randomId(): string;
  defaultCwd(): string;
}

export interface LaunchOptions {
  command?: string;
  intervalSeconds?: number;
  logFile?: string;
  notifyOn?: string[];
  heartbeatMinutes?: number;
  label?: string;
  coalesceSeconds?: number;
  maxLines?: number;
  cwd?: string;
  timeoutSeconds?: number;
}

export interface WatcherMeta {
  id: string;
  label: string;
  mode: MonitorMode;
  watchingFor: string;
  startedAt: string;
  lastEventAt: string | null;
  eventCount: number;
  alive: boolean;
}

export interface MonitorRuntime {
  /**
   * Start a watcher. Fully synchronous: the active-count check and the slot
   * reservation happen with no awaits in between, so concurrent tool calls
   * cannot oversubscribe the limit. Throws MonitorLimitError at the cap
   * before any process, timer, or file watcher is created.
   */
  launch(opts: LaunchOptions): WatcherMeta;
  /** Metas for all active watchers (map membership defines "active"). */
  list(): WatcherMeta[];
  get(id: string): WatcherMeta | undefined;
  /** Stop one watcher. Returns its meta, or undefined when not active. */
  stop(id: string): WatcherMeta | undefined;
  /** Stop every active watcher atomically; returns the stopped metas. */
  stopAll(options?: StopAllOptions): WatcherMeta[];
  activeCount(): number;
  /** Whether the shared heartbeat scheduler currently has a live timer. */
  heartbeatSchedulerActive(): boolean;
}

export interface StopAllOptions {
  /**
   * Follow SIGTERM with an immediate SIGKILL instead of the bounded 3s
   * escalation timer. Used for `quit` shutdown: the Pi process exits before
   * any escalation timer could ever fire, so waiting would leak children.
   */
  immediateKill?: boolean;
}

/** Thrown by `launch()` when the active-watcher cap is reached. */
export class MonitorLimitError extends Error {
  constructor(max: number) {
    super(
      `${max} active monitors; use monitor_status, then monitor_kill ` +
        `(id "*" stops all) before starting another.`,
    );
    this.name = "MonitorLimitError";
  }
}
