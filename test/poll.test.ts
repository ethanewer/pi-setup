import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";

test("poll assembles complete lines across chunks and matches on poll completion", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "ssh box check", intervalSeconds: 30, coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  child.pushStdout("erro");
  child.pushStdout("r: node down\nALIVE");
  child.pushStdout("=1\n");
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0, "nothing until the poll exits");
  child.exit(0);
  h.clock.advance(0);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error: node down/);
});

test("poll compares complete line sets and never replays identical old lines", () => {
  const h = makeHarness();
  h.runtime.launch({
    command: "tail log",
    intervalSeconds: 30,
    coalesceSeconds: 0,
    notifyOn: ["error"],
  });

  // Tick 1: one error line.
  h.proc.spawned[0]!.child.pushStdout("error one\nnormal line\n");
  h.proc.spawned[0]!.child.exit(0);
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // Tick 2: same output plus a new error → only the new line is pushed.
  h.clock.advance(30_000);
  assert.equal(h.proc.spawned.length, 2);
  h.proc.spawned[1]!.child.pushStdout("error one\nnormal line\nerror two\n");
  h.proc.spawned[1]!.child.exit(0);
  h.clock.advance(0);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 2);
  assert.equal(events[1]!.message.content.includes("error one"), false);
  assert.match(events[1]!.message.content, /error two/);

  // Tick 3: identical output → nothing new.
  h.clock.advance(30_000);
  h.proc.spawned[2]!.child.pushStdout("error one\nnormal line\nerror two\n");
  h.proc.spawned[2]!.child.exit(0);
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 2);
});

test("poll bounds retained output to the tail", () => {
  const h = makeHarness();
  h.runtime.launch({
    command: "chatty",
    intervalSeconds: 30,
    coalesceSeconds: 0,
    notifyOn: ["error"],
  });
  const child = h.proc.lastChild();
  child.pushStdout("error head\n");
  // 300 KiB of filler pushes the head line out of the retained window.
  const filler = ("x".repeat(120) + "\n").repeat(2560);
  child.pushStdout(filler);
  child.pushStdout("error tail\n");
  child.exit(0);
  h.clock.advance(0);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.equal(events[0]!.message.content.includes("error head"), false);
  assert.match(events[0]!.message.content, /error tail/);
});

test("stopping a poll watcher terminates the in-flight poll child's process group", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "slow-check", intervalSeconds: 30 });
  const inFlight = h.proc.lastChild();
  assert.equal(inFlight.hasExited, false);

  h.runtime.stop(meta.id);
  assert.deepEqual(h.proc.kills, [{ pid: inFlight.pid, group: true, signal: "SIGTERM" }]);
  h.clock.advance(3000);
  assert.deepEqual(h.proc.kills[1], { pid: inFlight.pid, group: true, signal: "SIGKILL" });

  // Interval is cancelled: no further polls are spawned.
  h.clock.advance(300_000);
  assert.equal(h.proc.spawned.length, 1);
});

test("poll results arriving after stop are suppressed", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "check", intervalSeconds: 30, coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  child.pushStdout("error: too late\n");
  h.runtime.stop(meta.id);
  child.exit(0);
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});

test("poll interval is clamped to a 2s minimum", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "check", intervalSeconds: 0.1 });
  assert.equal(h.proc.spawned.length, 1);
  h.clock.advance(1999);
  assert.equal(h.proc.spawned.length, 1);
  h.clock.advance(1);
  assert.equal(h.proc.spawned.length, 2);
});

test("a failed poll spawn reports once and retries next tick", () => {
  const h = makeHarness();
  h.proc.spawnError = new Error("ssh gone");
  h.runtime.launch({ command: "check", intervalSeconds: 30 });
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /POLL SPAWN ERROR: ssh gone/);
  assert.equal(h.runtime.activeCount(), 1, "watcher stays alive; next tick retries");

  h.proc.spawnError = null;
  h.clock.advance(30_000);
  assert.equal(h.proc.spawned.length, 1);
});
