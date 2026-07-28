import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";

test("coalesced output buffered before a kill is dropped, not delivered", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job", coalesceSeconds: 2 });
  h.proc.lastChild().pushStdout("error: about to be killed\n");
  h.runtime.stop(meta.id);
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});

test("chunks arriving after a kill are ignored", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job", coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  h.runtime.stop(meta.id);
  child.pushStdout("error: late output\n");
  child.pushStderr("fatal: more late output\n");
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});

test("a pending file debounce read is cancelled by stop", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  const meta = h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0 });
  h.files.append("/log/app", "error: buffered\n"); // schedules the 150ms debounce
  h.runtime.stop(meta.id);
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});

test("stop() is idempotent", () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job" });
  assert.ok(h.runtime.stop(meta.id));
  assert.equal(h.runtime.stop(meta.id), undefined);
  assert.equal(h.runtime.stopAll().length, 0);
  // Only the first stop signaled the child.
  assert.equal(h.proc.kills.filter((k) => k.signal === "SIGTERM").length, 1);
});

test("no timers leak after stopping watchers of every mode", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  h.runtime.launch({ command: "spawned", timeoutSeconds: 30, heartbeatMinutes: 5 });
  h.runtime.launch({ command: "polled", intervalSeconds: 30 });
  h.runtime.launch({ logFile: "/log/app" });
  h.runtime.stopAll();
  // Children never exit, so their bounded SIGKILL escalation timers are the
  // only remaining ones; after they fire, nothing is left.
  h.clock.advance(3000);
  assert.equal(h.clock.pendingCount(), 0);
});
