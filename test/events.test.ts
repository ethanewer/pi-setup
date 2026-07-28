import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";

test("spawn mode applies the notifyOn matcher and coalesces matched lines", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job", coalesceSeconds: 2 });
  const child = h.proc.lastChild();

  child.pushStdout("just some noise\nstep 12 loss=0.5\n");
  h.clock.advance(2000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0, "unmatched lines stay silent");

  child.pushStdout("checkpoint saved\nerror: disk full\n");
  h.clock.advance(2000);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1, "rapid matches coalesce into one message");
  assert.match(events[0]!.message.content, /checkpoint saved\nerror: disk full/);
  assert.equal(events[0]!.options?.triggerTurn, true);
  assert.equal(events[0]!.options?.deliverAs, "steer");
  assert.deepEqual(events[0]!.message.details, { id: meta.id });
});

test("lines split across chunks are assembled before matching", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "job", coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  child.pushStdout("erro");
  child.pushStderr(""); // interleaved empty chunk is harmless
  child.pushStdout("r: it broke\nok");
  h.clock.advance(0);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error: it broke/);
});

test("natural exit flushes buffered output, emits one exit event, and releases the watcher", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job", coalesceSeconds: 60 });
  const child = h.proc.lastChild();

  child.pushStdout("all done\n");
  child.pushStdout("final: success"); // no trailing newline
  child.exit(0);

  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 2);
  assert.match(events[0]!.message.content, /all done\nfinal: success/);
  assert.match(events[1]!.message.content, /PROCESS EXITED \(code=0 signal=none\)/);
  assert.equal(events[1]!.options?.triggerTurn, true);
  assert.equal(h.runtime.activeCount(), 0);
  assert.equal(h.runtime.get(meta.id), undefined);

  // No stray timers (coalescer flush was synchronous, cleanups ran).
  h.clock.advance(120_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 2);
});

test("a killed watcher emits no exit event and signals the process group with bounded escalation", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job" });
  const child = h.proc.lastChild();

  h.runtime.stop(meta.id);
  assert.deepEqual(h.proc.kills, [{ pid: child.pid, group: true, signal: "SIGTERM" }]);

  // Child ignores SIGTERM: escalation fires at 3s.
  h.clock.advance(3000);
  assert.deepEqual(h.proc.kills[1], { pid: child.pid, group: true, signal: "SIGKILL" });

  child.exit(null, "SIGKILL");
  h.clock.advance(10_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});

test("SIGKILL escalation is cancelled when the child exits in time", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job" });
  const child = h.proc.lastChild();
  h.runtime.stop(meta.id);
  child.exit(null, "SIGTERM"); // exits promptly after SIGTERM
  h.clock.advance(10_000);
  assert.deepEqual(h.proc.kills, [{ pid: child.pid, group: true, signal: "SIGTERM" }]);
});

test("group-kill falls back to direct child signaling when unavailable", () => {
  const h = makeHarness();
  h.proc.groupKillSupported = false;
  const meta = h.runtime.launch({ command: "job" });
  const child = h.proc.lastChild();
  h.runtime.stop(meta.id);
  assert.deepEqual(h.proc.kills, [{ pid: child.pid, group: false, signal: "SIGTERM" }]);
});

test("timeout emits one TIMEOUT event, stops the watcher, and suppresses the exit message", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job", timeoutSeconds: 10 });
  const child = h.proc.lastChild();

  h.clock.advance(10_000);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /TIMEOUT after 10s — auto-stopping watcher/);
  assert.equal(events[0]!.options?.triggerTurn, true);
  assert.equal(h.runtime.activeCount(), 0);
  assert.ok(h.proc.kills.some((k) => k.signal === "SIGTERM" && k.pid === child.pid));

  child.exit(null, "SIGTERM");
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // The timeout releasing the slot means a new watcher fits.
  assert.equal(h.runtime.get(meta.id), undefined);
});

test("a stopped watcher's timeout never fires", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job", timeoutSeconds: 10 });
  h.runtime.stop(meta.id);
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});

test("synchronous spawn failure reports once and releases the slot", () => {
  const h = makeHarness();
  h.proc.spawnError = new Error("bash not found");
  const meta = h.runtime.launch({ command: "job" });
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /FAILED TO SPAWN: bash not found/);
  assert.equal(h.runtime.activeCount(), 0);
  assert.equal(h.runtime.get(meta.id), undefined);
});
