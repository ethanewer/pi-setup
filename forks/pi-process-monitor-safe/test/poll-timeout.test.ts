import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";

// A poll tick that never exits used to end the watcher permanently: the no-overlap guard
// stayed latched, every later tick returned early, and nothing was ever emitted again. The
// failure was silent, which for a poll watching a remote host (the case poll mode exists
// for) is indistinguishable from "the remote has nothing to report yet".

const contents = (h: ReturnType<typeof makeHarness>): string[] =>
  h.pi.sentOfType(MESSAGE_TYPE_EVENT).map((s: { message?: { content?: string } }) => s.message?.content ?? "");

test("a hung poll tick times out, is killed, and the watcher keeps polling", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "ssh box check", intervalSeconds: 30, coalesceSeconds: 0, notifyOn: ["error"] });
  const hung = h.proc.lastChild();
  assert.equal(h.proc.spawned.length, 1);

  // Never exits. Advance past the tick timeout.
  h.clock.advance(30_000);
  const timedOut = contents(h).filter((c) => c.includes("POLL TIMEOUT"));
  assert.equal(timedOut.length, 1, "the stuck tick is reported once");
  assert.ok(h.proc.kills.some((k) => k.pid === hung.pid), "the hung child was signalled");

  // The next interval must actually run rather than being blocked by the stuck tick.
  h.clock.advance(30_000);
  assert.ok(h.proc.spawned.length >= 2, `a later tick ran, saw ${h.proc.spawned.length} spawns`);

  // And a healthy tick afterwards still reports normally.
  const healthy = h.proc.lastChild();
  healthy.pushStdout("error: node down\n");
  healthy.exit(0);
  h.clock.advance(0);
  assert.ok(contents(h).some((c) => c.includes("error: node down")), "polling recovered");
});

test("a timed-out tick does not fire repeat notifications while it keeps failing", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "ssh box check", intervalSeconds: 30, coalesceSeconds: 0 });
  for (let i = 0; i < 5; i++) h.clock.advance(30_000); // five hung ticks in a row
  const timedOut = contents(h).filter((c) => c.includes("POLL TIMEOUT"));
  assert.equal(timedOut.length, 1, "the existing failure latch still suppresses repeats");
});

test("a tick that exits normally never reports a timeout", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "ssh box check", intervalSeconds: 30, coalesceSeconds: 0, notifyOn: ["error"] });
  for (let i = 0; i < 3; i++) {
    const child = h.proc.lastChild();
    child.pushStdout(`error: tick ${i}\n`);
    child.exit(0);
    h.clock.advance(30_000);
  }
  assert.equal(contents(h).filter((c) => c.includes("POLL TIMEOUT")).length, 0);
  assert.equal(contents(h).filter((c) => c.includes("error: tick")).length, 3);
});

test("a timed-out child's late exit does not corrupt the tick that replaced it", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "ssh box check", intervalSeconds: 30, coalesceSeconds: 0 });
  const hung = h.proc.lastChild();

  h.clock.advance(29_000); // tick A times out; the child is signalled but does not die
  assert.ok(contents(h).some((c) => c.includes("POLL TIMEOUT")));
  h.clock.advance(1_000); // interval fires: tick B starts
  assert.equal(h.proc.spawned.length, 2);
  const live = h.proc.lastChild();
  assert.notEqual(live.pid, hung.pid);

  // Child A finally dies, long after its tick was abandoned. Its handlers must not touch
  // state that now belongs to tick B.
  hung.exit(null, "SIGKILL");

  // B is still running, so the next interval must still be suppressed.
  h.clock.advance(30_000);
  const spawnedWhileBAlive = h.proc.spawned.length;

  // And B must still be covered by its own timeout.
  assert.ok(
    h.proc.kills.some((k) => k.pid === live.pid),
    "tick B kept its timeout and was killed when it hung too",
  );
  assert.equal(spawnedWhileBAlive, 3, "exactly one tick started after B timed out, not two");
});
