/**
 * Production adapters backing the injected runtime interfaces with real
 * Node.js timers, child processes, and filesystem access.
 */

import { spawn, type ChildProcess } from "node:child_process";
import * as fs from "node:fs";
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
  constructor(private readonly child: ChildProcess) {}

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
    this.child.on("exit", (code, signal) => cb(code, signal));
  }

  onError(cb: (error: Error) => void): void {
    this.child.on("error", cb);
  }

  kill(signal: KillSignal): void {
    if (!this.child.killed && this.child.exitCode === null && this.child.signalCode === null) {
      this.child.kill(signal);
    }
  }
}

/**
 * Spawn/poll children run in their own process group (`detached: true`) on
 * Unix so teardown can signal the whole tree via the negative PID. On
 * platforms without process groups, `killGroup` returns false and the runtime
 * falls back to signaling the direct child.
 */
export function createRealProcessAdapter(): ProcessAdapter {
  const detached = process.platform !== "win32";
  return {
    spawn(command: string, cwd: string): ChildHandle {
      const child = spawn("bash", ["-c", command], {
        cwd,
        detached,
        stdio: ["ignore", "pipe", "pipe"],
      });
      return new RealChildHandle(child);
    },
    killGroup(pid: number, signal: KillSignal): boolean {
      if (process.platform === "win32") return false;
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
