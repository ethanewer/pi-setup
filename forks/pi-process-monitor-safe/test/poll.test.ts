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

test("a head-truncated first retained line is discarded before matching and dedup", () => {
  const h = makeHarness();
  h.runtime.launch({
    command: "chatty",
    intervalSeconds: 30,
    coalesceSeconds: 0,
    notifyOn: ["error"],
  });
  const child = h.proc.lastChild();
  // One ~280 KiB line: bounded retention truncates it from the head, so the
  // first retained "line" is a partial tail that must never be matched.
  child.pushStdout("x".repeat(280 * 1024) + "error partial\n");
  child.pushStdout("error complete\n");
  child.exit(0);
  h.clock.advance(0);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error complete/);
  assert.equal(events[0]!.message.content.includes("error partial"), false);
});

test("poll ticks do not overlap: ticks are skipped while the prior child is in flight", () => {
  const h = makeHarness();
  h.runtime.launch({
    command: "slow-ssh-check",
    intervalSeconds: 30,
    coalesceSeconds: 0,
    notifyOn: ["error"],
  });
  assert.equal(h.proc.spawned.length, 1);

  // A tick still in flight suppresses the next one, so concurrent children never pile up.
  // This used to assert that three whole intervals could elapse that way, which quietly
  // encoded the hang-forever bug: a child that never exits held the guard permanently and
  // the watcher went silent. The guard is now bounded by the per-tick timeout, so this
  // stays inside that window; test/poll-timeout.test.ts covers what happens past it.
  h.clock.advance(28_000);
  assert.equal(h.proc.spawned.length, 1);

  // Once the child completes, the next tick polls again and diffing works.
  h.proc.lastChild().pushStdout("error one\n");
  h.proc.lastChild().exit(0);
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);
  h.clock.advance(30_000);
  assert.equal(h.proc.spawned.length, 2);

  // An errored in-flight child also re-enables ticking.
  h.proc.lastChild().fail(new Error("pipe burst"));
  h.clock.advance(30_000);
  assert.equal(h.proc.spawned.length, 3);
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
  h.proc.lastChild().exit(0); // complete the first poll so no tick is overlap-skipped
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

test("consecutive poll spawn failures are latched to one event until a poll succeeds", () => {
  const h = makeHarness();
  h.proc.spawnError = new Error("ssh gone");
  h.runtime.launch({ command: "check", intervalSeconds: 30, coalesceSeconds: 0 });
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // Three more failing ticks: still just the first event.
  h.clock.advance(90_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // A successfully completed poll re-arms the latch…
  h.proc.spawnError = null;
  h.clock.advance(30_000);
  h.proc.lastChild().exit(0);
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // …so the next failure streak reports exactly once more.
  h.proc.spawnError = new Error("ssh gone again");
  h.clock.advance(60_000);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 2);
  assert.match(events[1]!.message.content, /POLL SPAWN ERROR: ssh gone again/);
});

test("poll runtime errors are latched, and an errored poll neither diffs output nor re-arms", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "check", intervalSeconds: 30, coalesceSeconds: 0, notifyOn: ["error"] });
  // Tick 1 completes and establishes the baseline line set.
  h.proc.spawned[0]!.child.pushStdout("error one\n");
  h.proc.spawned[0]!.child.exit(0);
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // Ticks 2 and 3 error mid-run: exactly one POLL ERROR event total.
  h.clock.advance(30_000);
  h.proc.spawned[1]!.child.pushStdout("truncated garbage that must not be diffed");
  h.proc.spawned[1]!.child.fail(new Error("pipe burst"));
  h.clock.advance(30_000);
  h.proc.spawned[2]!.child.fail(new Error("pipe burst"));
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 2);
  assert.match(events[1]!.message.content, /POLL ERROR: pipe burst/);

  // Tick 4 succeeds with the same old line: not replayed, because the
  // baseline from tick 1 survived the errored ticks; the latch re-arms.
  h.clock.advance(30_000);
  h.proc.spawned[3]!.child.pushStdout("error one\n");
  h.proc.spawned[3]!.child.exit(0);
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 2);

  h.clock.advance(30_000);
  h.proc.spawned[4]!.child.fail(new Error("burst again"));
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 3);
});

test("an errored poll child is untracked and never signaled by a later stop", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "check", intervalSeconds: 30 });
  h.proc.lastChild().fail(new Error("boom"));
  h.runtime.stop(meta.id);
  assert.equal(h.proc.kills.length, 0, "failed child handle was removed from tracking");
  h.clock.advance(10_000);
  assert.equal(h.clock.pendingCount(), 0, "no escalation timer for a dead child");
});
