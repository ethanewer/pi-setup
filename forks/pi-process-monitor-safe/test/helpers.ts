/**
 * Deterministic test doubles: a manually advanced clock, scripted child
 * processes, an in-memory filesystem, and a recording mock of pi's
 * ExtensionAPI / ExtensionContext.
 */

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type {
  ChildHandle,
  Clock,
  FileAdapter,
  KillSignal,
  ProcessAdapter,
  TimerHandle,
} from "../extensions/monitor/types.ts";
import {
  registerMonitorExtension,
  type MonitorAdapters,
} from "../extensions/monitor/extension.ts";
import type { MonitorRuntime } from "../extensions/monitor/types.ts";

// ---------------------------------------------------------------- fake clock

interface FakeTimer {
  at: number;
  interval: number | null;
  fn: () => void;
  seq: number;
}

export class FakeClock implements Clock {
  time = 0;
  private seq = 0;
  private timers = new Set<FakeTimer>();

  now(): number {
    return this.time;
  }

  setTimeout(fn: () => void, ms: number): TimerHandle {
    const timer: FakeTimer = { at: this.time + Math.max(0, ms), interval: null, fn, seq: this.seq++ };
    this.timers.add(timer);
    return timer;
  }

  clearTimeout(handle: TimerHandle): void {
    this.timers.delete(handle as FakeTimer);
  }

  setInterval(fn: () => void, ms: number): TimerHandle {
    const period = Math.max(1, ms);
    const timer: FakeTimer = { at: this.time + period, interval: period, fn, seq: this.seq++ };
    this.timers.add(timer);
    return timer;
  }

  clearInterval(handle: TimerHandle): void {
    this.timers.delete(handle as FakeTimer);
  }

  pendingCount(): number {
    return this.timers.size;
  }

  /** Advance fake time, firing due timers in deterministic (time, seq) order. */
  advance(ms: number): void {
    const target = this.time + ms;
    for (;;) {
      let next: FakeTimer | null = null;
      for (const timer of this.timers) {
        if (timer.at > target) continue;
        if (!next || timer.at < next.at || (timer.at === next.at && timer.seq < next.seq)) {
          next = timer;
        }
      }
      if (!next) break;
      this.time = next.at;
      if (next.interval !== null) {
        next.at += next.interval;
        next.seq = this.seq++;
      } else {
        this.timers.delete(next);
      }
      next.fn();
    }
    this.time = target;
  }
}

// ------------------------------------------------------------- fake process

export interface KillRecord {
  pid: number | undefined;
  group: boolean;
  signal: KillSignal;
}

export class FakeChild implements ChildHandle {
  exitedNaturally = false;
  private stdoutCbs: Array<(chunk: string) => void> = [];
  private stderrCbs: Array<(chunk: string) => void> = [];
  private exitCbs: Array<(code: number | null, signal: string | null) => void> = [];
  private errorCbs: Array<(error: Error) => void> = [];
  private done = false;

  constructor(
    readonly pid: number | undefined,
    private readonly recordKill: (record: KillRecord) => void,
  ) {}

  onStdout(cb: (chunk: string) => void): void {
    this.stdoutCbs.push(cb);
  }
  onStderr(cb: (chunk: string) => void): void {
    this.stderrCbs.push(cb);
  }
  onExit(cb: (code: number | null, signal: string | null) => void): void {
    this.exitCbs.push(cb);
  }
  onError(cb: (error: Error) => void): void {
    this.errorCbs.push(cb);
  }
  kill(signal: KillSignal): void {
    this.recordKill({ pid: this.pid, group: false, signal });
  }

  // ---- test controls
  pushStdout(chunk: string): void {
    for (const cb of this.stdoutCbs) cb(chunk);
  }
  pushStderr(chunk: string): void {
    for (const cb of this.stderrCbs) cb(chunk);
  }
  exit(code: number | null = 0, signal: string | null = null): void {
    if (this.done) return;
    this.done = true;
    this.exitedNaturally = true;
    for (const cb of this.exitCbs) cb(code, signal);
  }
  /**
   * Mirrors the real adapter contract: error callbacks fire first, then exit
   * callbacks finalize exactly once (an errored child never reaches `close`).
   */
  fail(error: Error): void {
    for (const cb of this.errorCbs) cb(error);
    if (this.done) return;
    this.done = true;
    for (const cb of this.exitCbs) cb(null, null);
  }
  get hasExited(): boolean {
    return this.done;
  }
}

export class FakeProc implements ProcessAdapter {
  spawned: Array<{ command: string; cwd: string; child: FakeChild }> = [];
  kills: KillRecord[] = [];
  spawnError: Error | null = null;
  groupKillSupported = true;
  private nextPid = 1000;

  spawn(command: string, cwd: string): ChildHandle {
    if (this.spawnError) throw this.spawnError;
    const child = new FakeChild(this.nextPid++, (record) => this.kills.push(record));
    this.spawned.push({ command, cwd, child });
    return child;
  }

  killGroup(pid: number, signal: KillSignal): boolean {
    if (!this.groupKillSupported) return false;
    this.kills.push({ pid, group: true, signal });
    return true;
  }

  lastChild(): FakeChild {
    const entry = this.spawned[this.spawned.length - 1];
    if (!entry) throw new Error("no child spawned");
    return entry.child;
  }
}

// ---------------------------------------------------------------- fake files

export class FakeFiles implements FileAdapter {
  watchSupported = true;
  private contents = new Map<string, string>();
  private watchers = new Map<string, Set<() => void>>();

  statSize(path: string): number | null {
    const content = this.contents.get(path);
    return content === undefined ? null : Buffer.byteLength(content, "utf8");
  }

  readSlice(path: string, start: number, end: number): string {
    const content = this.contents.get(path);
    if (content === undefined) throw new Error(`ENOENT: ${path}`);
    return Buffer.from(content, "utf8").subarray(start, end).toString("utf8");
  }

  watch(path: string, onChange: () => void): (() => void) | null {
    if (!this.watchSupported) return null;
    let set = this.watchers.get(path);
    if (!set) {
      set = new Set();
      this.watchers.set(path, set);
    }
    set.add(onChange);
    return () => set.delete(onChange);
  }

  // ---- test controls
  set(path: string, content: string): void {
    this.contents.set(path, content);
  }
  append(path: string, content: string): void {
    this.contents.set(path, (this.contents.get(path) ?? "") + content);
    this.notify(path);
  }
  notify(path: string): void {
    for (const cb of this.watchers.get(path) ?? []) cb();
  }
  watcherCount(path: string): number {
    return this.watchers.get(path)?.size ?? 0;
  }
}

// ------------------------------------------------------------------- mock pi

export interface SentMessage {
  message: { customType: string; content: string; display: boolean; details?: unknown };
  options: { triggerTurn?: boolean; deliverAs?: string } | undefined;
}

type ToolExecute = (
  toolCallId: string,
  params: any,
  signal: AbortSignal | undefined,
  onUpdate: unknown,
  ctx: ExtensionContext,
) => Promise<{ content: Array<{ type: string; text: string }>; details: any }>;

interface RegisteredTool {
  name: string;
  description: string;
  parameters: unknown;
  execute: ToolExecute;
}

interface RegisteredCommand {
  description?: string;
  handler: (args: string, ctx: any) => Promise<void>;
  getArgumentCompletions?: (prefix: string) => unknown;
}

export class MockPi {
  tools = new Map<string, RegisteredTool>();
  commands = new Map<string, RegisteredCommand>();
  renderers = new Map<string, unknown>();
  handlers = new Map<string, Array<(event: any, ctx: any) => Promise<unknown> | unknown>>();
  sent: SentMessage[] = [];
  appendedEntries: Array<{ customType: string; data: unknown }> = [];

  on(event: string, handler: (event: any, ctx: any) => Promise<unknown> | unknown): void {
    const list = this.handlers.get(event) ?? [];
    list.push(handler);
    this.handlers.set(event, list);
  }

  registerTool(tool: RegisteredTool): void {
    this.tools.set(tool.name, tool);
  }

  registerCommand(name: string, options: RegisteredCommand): void {
    this.commands.set(name, options);
  }

  registerMessageRenderer(customType: string, renderer: unknown): void {
    this.renderers.set(customType, renderer);
  }

  sendMessage(message: SentMessage["message"], options?: SentMessage["options"]): void {
    this.sent.push({ message, options });
  }

  appendEntry(customType: string, data?: unknown): void {
    this.appendedEntries.push({ customType, data });
  }

  // ---- test controls
  async emit(event: string, eventObj: unknown, ctx: unknown): Promise<void> {
    for (const handler of this.handlers.get(event) ?? []) {
      await handler(eventObj, ctx);
    }
  }

  tool(name: string): RegisteredTool {
    const tool = this.tools.get(name);
    if (!tool) throw new Error(`tool ${name} not registered`);
    return tool;
  }

  command(name: string): RegisteredCommand {
    const command = this.commands.get(name);
    if (!command) throw new Error(`command ${name} not registered`);
    return command;
  }

  sentOfType(customType: string): SentMessage[] {
    return this.sent.filter((s) => s.message.customType === customType);
  }
}

// ------------------------------------------------------------------ mock ctx

export interface MockCtxOptions {
  hasUI?: boolean;
  idle?: boolean;
  entries?: unknown[];
  cwd?: string;
  /** When false, the mock sessionManager lacks appendCustomMessageEntry. */
  supportsDirectAppend?: boolean;
}

export interface DirectAppend {
  customType: string;
  content: string;
  display: boolean;
  details: unknown;
}

export function makeCtx(options: MockCtxOptions = {}) {
  const notices: Array<{ message: string; level: string }> = [];
  const directAppends: DirectAppend[] = [];
  const sessionManager: Record<string, unknown> = {
    getEntries: () => options.entries ?? [],
  };
  if (options.supportsDirectAppend !== false) {
    sessionManager.appendCustomMessageEntry = (
      customType: string,
      content: string,
      display: boolean,
      details: unknown,
    ): string => {
      directAppends.push({ customType, content, display, details });
      return `entry-${directAppends.length}`;
    };
  }
  const hasUI = options.hasUI ?? true;
  const ctx = {
    hasUI,
    mode: hasUI ? "tui" : "print",
    cwd: options.cwd ?? "/tmp",
    isIdle: () => options.idle ?? true,
    sessionManager,
    ui: {
      notify: (message: string, level: string) => {
        if (!hasUI) throw new Error("ui.notify called without UI");
        notices.push({ message, level });
      },
    },
  };
  return { ctx: ctx as unknown as ExtensionContext, notices, directAppends };
}

// -------------------------------------------------------------- test harness

export interface Harness {
  pi: MockPi;
  clock: FakeClock;
  proc: FakeProc;
  files: FakeFiles;
  runtime: MonitorRuntime;
}

let idCounter = 0;

export function makeHarness(): Harness {
  const pi = new MockPi();
  const clock = new FakeClock();
  const proc = new FakeProc();
  const files = new FakeFiles();
  const adapters: MonitorAdapters = {
    clock,
    proc,
    files,
    randomId: () => `w${String(idCounter++).padStart(4, "0")}`,
    defaultCwd: () => "/default",
  };
  const runtime = registerMonitorExtension(pi as unknown as ExtensionAPI, adapters);
  return { pi, clock, proc, files, runtime };
}

/** Launch through the monitor tool with a default ctx; returns watcher meta. */
export async function launchViaTool(
  h: Harness,
  params: Record<string, unknown>,
  ctx?: ExtensionContext,
): Promise<{ id: string; mode: string }> {
  const context = ctx ?? makeCtx().ctx;
  const result = await h.pi.tool("monitor").execute("t1", params, undefined, undefined, context);
  return result.details.watcher;
}
