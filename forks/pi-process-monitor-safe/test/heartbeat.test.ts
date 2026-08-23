import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import {
  MESSAGE_TYPE_EVENT,
  MESSAGE_TYPE_HEARTBEAT,
} from "../extensions/monitor/types.ts";

test("heartbeats are off unless requested", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "job" });
  assert.equal(h.runtime.heartbeatSchedulerActive(), false);
  h.clock.advance(60 * 60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length, 0);
});

test("fractional heartbeatMinutes fires on the sub-minute schedule", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "job", heartbeatMinutes: 0.5 });
  h.clock.advance(29_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length, 0, "not due yet");
  h.clock.advance(2_000);
  const beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(beats.length, 1, "due at 30s");
});

test("all due watchers aggregate into one turn-triggering heartbeat message", () => {
  const h = makeHarness();
  const a = h.runtime.launch({ command: "a", heartbeatMinutes: 1 });
  const b = h.runtime.launch({ command: "b", heartbeatMinutes: 1 });
  const c = h.runtime.launch({ command: "c", heartbeatMinutes: 2 });
  assert.equal(h.runtime.heartbeatSchedulerActive(), true);

  h.clock.advance(60_000);
  let beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(beats.length, 1, "a and b share one message");
  assert.deepEqual(beats[0]!.message.details, { watcherIds: [a.id, b.id] });
  assert.equal(beats[0]!.options?.triggerTurn, true);
  assert.equal(beats[0]!.options?.deliverAs, "steer");
  assert.match(beats[0]!.message.content, /2 watcher\(s\) still running/);

  // At 120s: a and b are due again, and c is due for the first time.
  h.clock.advance(60_000);
  beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(beats.length, 2);
  assert.deepEqual(beats[1]!.message.details, { watcherIds: [a.id, b.id, c.id] });
});

test("each due time advances by its own interval", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "a", heartbeatMinutes: 1 });
  h.runtime.launch({ command: "c", heartbeatMinutes: 3 });

  h.clock.advance(6 * 60_000);
  const beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  // a beats at 1,2,3,4,5,6 minutes; c joins at 3 and 6.
  assert.equal(beats.length, 6);
  const withC = beats.filter(
    (b) => (b.message.details as { watcherIds: string[] }).watcherIds.length === 2,
  );
  assert.equal(withC.length, 2);
});

test("a real event since the preceding interval substitutes for that heartbeat", () => {
  const h = makeHarness();
  const a = h.runtime.launch({ command: "a", heartbeatMinutes: 1, coalesceSeconds: 0 });
  const b = h.runtime.launch({ command: "b", heartbeatMinutes: 1 });

  // Real event for a at t=30s.
  h.clock.advance(30_000);
  h.proc.spawned[0]!.child.pushStdout("checkpoint saved\n");
  h.clock.advance(0);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 1);

  // t=60s: only b is due; a's real event substituted.
  h.clock.advance(30_000);
  const beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(beats.length, 1);
  assert.deepEqual(beats[0]!.message.details, { watcherIds: [b.id] });

  // t=120s: no new real events → a beats again.
  h.clock.advance(60_000);
  const later = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(later.length, 2);
  assert.deepEqual(later[1]!.message.details, { watcherIds: [a.id, b.id] });
});

test("heartbeats do not update lastEventAt or eventCount", () => {
  const h = makeHarness();
  const a = h.runtime.launch({ command: "a", heartbeatMinutes: 1 });
  h.clock.advance(5 * 60_000);
  assert.ok(h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length >= 5, "beats keep coming");
  const meta = h.runtime.get(a.id)!;
  assert.equal(meta.eventCount, 0);
  assert.equal(meta.lastEventAt, null);
});

test("killing, timing out, or shutting down removes watchers from heartbeat scheduling", async () => {
  const h = makeHarness();
  const killed = h.runtime.launch({ command: "a", heartbeatMinutes: 1 });
  const timed = h.runtime.launch({ command: "b", heartbeatMinutes: 1, timeoutSeconds: 90 });
  h.runtime.launch({ command: "c", heartbeatMinutes: 1 });

  h.runtime.stop(killed.id);
  h.clock.advance(60_000);
  let beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(beats.length, 1);
  assert.equal(
    (beats[0]!.message.details as { watcherIds: string[] }).watcherIds.includes(killed.id),
    false,
  );

  h.clock.advance(60_000); // b times out at 90s, before the 120s tick
  beats = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT);
  assert.equal(beats.length, 2);
  assert.equal(
    (beats[1]!.message.details as { watcherIds: string[] }).watcherIds.includes(timed.id),
    false,
  );

  h.runtime.stopAll();
  assert.equal(h.runtime.heartbeatSchedulerActive(), false);
  const count = h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length;
  h.clock.advance(10 * 60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length, count);
});

test("the shared scheduler ticks even when one watcher's interval is long", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "a", heartbeatMinutes: 10 });
  h.clock.advance(9 * 60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length, 0);
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_HEARTBEAT).length, 1);
});
