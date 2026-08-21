/**
 * Production adapters backing the injected runtime interfaces with real
 * Node.js timers, child processes, and filesystem access.
 */

import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  type ChildHandle,
  type Clock,
  type FileAdapter,
  type KillSignal,
  type ProcessAdapter,
} from "./types.ts";

export function createRealClock(): Clock {
  return {
    now: () => Date.now(),
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (handle) => clearTimeout(handle as NodeJS.Timeout),
    setInterval: (fn, ms) => setInterval(fn, ms),
    clearInterval: (handle) => clearInterval(handle as NodeJS.Timeout),
  };
}

class RealChildHandle implements ChildHandle {
  private code: number | null = null;
  private signal: string | null = null;
  private finalized = false;
  private readonly exitCbs: Array<(code: number | null, signal: string | null) => void> = [];
  private readonly errorCbs: Array<(error: Error) => void> = [];

  constructor(private readonly child: ChildProcess) {
    child.on("exit", (code, signal) => {
      this.code = code;
      this.signal = signal;
    });
    // Finalize on `close`, not `exit`: `close` fires only after both stdio
    // pipes have delivered everything, so exit callbacks can never race (and
    // drop) the final output chunks.
    child.on("close", (code, signal) => this.finalize(code ?? this.code, signal ?? this.signal));
    child.on("error", (error) => {
      for (const cb of [...this.errorCbs]) cb(error);
      // A child that failed to spawn may never reach `close`; finalize here
      // (after the error callbacks) so callers can always untrack it.
      this.finalize(this.code, this.signal);
    });
  }

  private finalize(code: number | null, signal: string | null): void {
    if (this.finalized) return;
    this.finalized = true;
    this.code = code;
    this.signal = signal;
    for (const cb of [...this.exitCbs]) cb(code, signal);
  }

  get pid(): number | undefined {
    return this.child.pid;
  }

  onStdout(cb: (chunk: string) => void): void {
    this.child.stdout?.on("data", (data: Buffer | string) => cb(data.toString()));
  }

  onStderr(cb: (chunk: string) => void): void {
    this.child.stderr?.on("data", (data: Buffer | string) => cb(data.toString()));
  }

  onExit(cb: (code: number | null, signal: string | null) => void): void {
    if (this.finalized) {
      cb(this.code, this.signal);
      return;
    }
    this.exitCbs.push(cb);
  }

  onError(cb: (error: Error) => void): void {
    this.errorCbs.push(cb);
  }

  kill(signal: KillSignal): void {
    // Gate only on actual exit: `child.killed` merely records that a signal
    // was sent, so checking it would swallow the SIGKILL escalation after a
    // SIGTERM that the child trapped or ignored.
    if (this.child.exitCode === null && this.child.signalCode === null) {
      this.child.kill(signal);
    }
  }
}

const WIN32 = process.platform === "win32";

function isWslBash(p: string): boolean {
  const normalized = p.replace(/\//g, "\\").toLowerCase();
  return (
    normalized.includes("\\windows\\system32\\bash.exe") ||
    normalized.includes("\\windows\\sysnative\\bash.exe") ||
    normalized.includes("\\windows\\syswow64\\bash.exe")
  );
}

function whichOnPath(name: string): string {
  const pathEnv = process.env.PATH || "";
  const delimiter = WIN32 ? ";" : ":";
  const exts = WIN32 ? (process.env.PATHEXT || ".EXE;.CMD;.BAT").split(";").concat("") : [""];
  for (const dir of pathEnv.split(delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = path.join(dir, name + ext);
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  return "";
}

/** Locate bash so spawn/poll commands use the same shell Pi requires on Windows. */
export function findBashCommand(): string {
  if (!WIN32) return "bash";
  const candidates = [
    process.env.PI_BASH,
    process.env.GIT_BASH,
    "C:\\Program Files\\Git\\bin\\bash.exe",
    "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
    "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
  ].filter((p): p is string => typeof p === "string" && p.length > 0);
  const git = whichOnPath("git");
  if (git) {
    const gitDir = path.dirname(git);
    candidates.push(
      path.join(gitDir, "bash.exe"),
      path.join(gitDir, "..", "bin", "bash.exe"),
      path.join(gitDir, "..", "usr", "bin", "bash.exe"),
    );
  }
  const fromPath = whichOnPath("bash");
  if (fromPath && /git/i.test(fromPath)) candidates.push(fromPath);
  for (const c of candidates) {
    if (c && fs.existsSync(c) && !isWslBash(c)) return c;
  }
  return "";
}

function killWindowsTree(pid: number, force: boolean): boolean {
  const args = ["/PID", String(pid), "/T"];
  if (force) args.push("/F");
  const result = spawnSync("taskkill", args, {
    stdio: "ignore",
    windowsHide: true,
  });
  // 0 = signaled, 128 = already gone. Anything else falls back to the direct child.
  return result.status === 0 || result.status === 128;
}

/**
 * Spawn/poll children run in their own process group (`detached: true`) on
 * Unix so teardown can signal the whole tree via the negative PID. On Windows
 * the same `detached` flag creates a new process tree, which `taskkill /T`
 * then tears down — SIGTERM without `/F`, SIGKILL with it.
 */
export function createRealProcessAdapter(): ProcessAdapter {
  const bash = findBashCommand();
  return {
    spawn(command: string, cwd: string): ChildHandle {
      const child = spawn(bash, ["-c", command], {
        cwd,
        detached: true,
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
      });
      return new RealChildHandle(child);
    },
    killGroup(pid: number, signal: KillSignal): boolean {
      if (WIN32) return killWindowsTree(pid, signal === "SIGKILL");
      try {
        process.kill(-pid, signal);
        return true;
      } catch {
        return false;
      }
    },
  };
}

export function createRealFileAdapter(): FileAdapter {
  return {
    statSize(path: string): number | null {
      try {
        return fs.statSync(path).size;
      } catch {
        return null;
      }
    },
    readSlice(path: string, start: number, end: number): string {
      const length = end - start;
      if (length <= 0) return "";
      const fd = fs.openSync(path, "r");
      try {
        const buf = Buffer.alloc(length);
        const read = fs.readSync(fd, buf, 0, length, start);
        return buf.subarray(0, read).toString("utf8");
      } finally {
        fs.closeSync(fd);
      }
    },
    watch(path: string, onChange: () => void): (() => void) | null {
      try {
        const watcher = fs.watch(path, onChange);
        return () => watcher.close();
      } catch {
        return null; // missing file: rely on the backstop poll
      }
    },
  };
}

export function randomWatcherId(): string {
  return Math.random().toString(36).slice(2, 11);
}
