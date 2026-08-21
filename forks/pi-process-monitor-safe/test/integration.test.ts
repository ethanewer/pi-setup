/**
 * Real-child integration smoke tests: everything else in test/ drives the
 * runtime with deterministic fakes; these tests use the production adapters
 * (real bash children, real timers, real process groups) to pin the behaviors
 * fakes cannot prove — that final pipe output is never dropped before the exit
 * event, and that stopping a watcher tears down the whole process tree
 * (POSIX process groups, `taskkill /T` on Windows).
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  createRealClock,
  createRealFileAdapter,
  createRealProcessAdapter,
  findBashCommand,
  randomWatcherId,
} from "../extensions/monitor/adapters.ts";
import { createMonitorRuntime } from "../extensions/monitor/runtime.ts";
import type { MonitorCustomMessage } from "../extensions/monitor/types.ts";

const isUnix = process.platform !== "win32";
const bashPath = findBashCommand();
const hasRealBash =
  bashPath.length > 0 && (process.platform !== "win32" || /git/i.test(bashPath));

function makeRealRuntime() {
  const sent: MonitorCustomMessage[] = [];
  const runtime = createMonitorRuntime({
    clock: createRealClock(),
    proc: createRealProcessAdapter(),
    files: createRealFileAdapter(),
    send: (message) => sent.push(message),
    randomId: randomWatcherId,
    defaultCwd: () => process.cwd(),
  });
  return { runtime, sent };
}

async function waitFor(cond: () => boolean, what: string, timeoutMs = 10_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!cond()) {
    if (Date.now() > deadline) throw new Error(`timed out waiting for ${what}`);
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

test("real spawn: final unterminated output arrives before the exit event", { skip: !hasRealBash }, async () => {
  const { runtime, sent } = makeRealRuntime();
  // No trailing newline: the last chunk is only delivered if exit handling
  // waits for the stdio pipes to close (Node 'close', not 'exit').
  runtime.launch({ command: "printf 'error: final chunk'", coalesceSeconds: 0 });

  await waitFor(() => sent.some((m) => m.content.includes("PROCESS EXITED")), "process exit event");
  const dataIdx = sent.findIndex((m) => m.content.includes("error: final chunk"));
  const exitIdx = sent.findIndex((m) => m.content.includes("PROCESS EXITED"));
  assert.notEqual(dataIdx, -1, "final chunk without a trailing newline was delivered");
  assert.ok(dataIdx < exitIdx, "output event precedes the exit event");
  assert.equal(runtime.activeCount(), 0, "natural exit released the slot");
});

test("real kill fallback: direct-child SIGKILL is still delivered after SIGTERM", { skip: !isUnix }, async () => {
  const proc = createRealProcessAdapter();
  // The child installs the TERM trap before printing "ready", so the later
  // SIGTERM is guaranteed to be ignored; only the SIGKILL escalation can end
  // it. Regression: ChildProcess.killed is true after the first kill() and
  // must not gate the second signal.
  const handle = proc.spawn("trap '' TERM; echo ready; while :; do sleep 1; done", process.cwd());
  let stdout = "";
  let exited = false;
  let exitSignal: string | null = null;
  handle.onStdout((chunk) => (stdout += chunk));
  handle.onExit((_code, signal) => {
    exited = true;
    exitSignal = signal;
  });
  try {
    await waitFor(() => stdout.includes("ready"), "TERM trap installed");
    handle.kill("SIGTERM");
    await new Promise((resolve) => setTimeout(resolve, 150));
    assert.equal(exited, false, "child traps SIGTERM and keeps running");
    handle.kill("SIGKILL");
    await waitFor(() => exited, "SIGKILL delivered after SIGTERM");
    assert.equal(exitSignal, "SIGKILL");
  } finally {
    if (handle.pid !== undefined) proc.killGroup(handle.pid, "SIGKILL");
  }
});

test("real kill: stopping a watcher terminates the whole process group", { skip: !isUnix }, async () => {
  const { runtime } = makeRealRuntime();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-monitor-safe-"));
  const pidFile = path.join(dir, "pid");
  // The background sleep is a grandchild of the adapter's bash; only a
  // process-group signal (not a direct-child SIGTERM) reaches it.
  const meta = runtime.launch({
    command: `sleep 300 & echo $! > ${pidFile}; wait`,
    coalesceSeconds: 0,
  });

  let sleepPid = 0;
  try {
    await waitFor(() => {
      try {
        sleepPid = Number(fs.readFileSync(pidFile, "utf8").trim());
        return Number.isInteger(sleepPid) && sleepPid > 0;
      } catch {
        return false;
      }
    }, "background sleep pid");
    assert.doesNotThrow(() => process.kill(sleepPid, 0), "sleep is running before the stop");

    runtime.stop(meta.id);
    await waitFor(() => {
      try {
        process.kill(sleepPid, 0);
        return false;
      } catch {
        return true; // ESRCH: the grandchild is gone
      }
    }, "process group teardown");
    assert.equal(runtime.activeCount(), 0);
  } finally {
    if (sleepPid > 0) {
      try {
        process.kill(sleepPid, "SIGKILL");
      } catch {
        /* already gone — the expected case */
      }
    }
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("real kill: taskkill /T stops a spawned bash child", { skip: process.platform !== "win32" || !hasRealBash }, async () => {
  const proc = createRealProcessAdapter();
  const handle = proc.spawn("sleep 300", process.cwd());
  let exited = false;
  handle.onExit(() => {
    exited = true;
  });
  try {
    await waitFor(() => handle.pid !== undefined, "bash child pid");
    assert.equal(proc.killGroup(handle.pid as number, "SIGKILL"), true);
    await waitFor(() => exited, "bash tree exited after taskkill");
  } finally {
    if (!exited && handle.pid !== undefined) proc.killGroup(handle.pid, "SIGKILL");
  }
});
