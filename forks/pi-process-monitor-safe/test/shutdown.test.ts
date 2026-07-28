import { test } from "node:test";
import assert from "node:assert/strict";
import { makeCtx, makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT, MESSAGE_TYPE_STOP_ALL } from "../extensions/monitor/types.ts";

function launchAllModes(h: ReturnType<typeof makeHarness>) {
  h.files.set("/log/app", "");
  return [
    h.runtime.launch({ command: "spawned", label: "sp" }),
    h.runtime.launch({ command: "polled", intervalSeconds: 30 }),
    h.runtime.launch({ logFile: "/log/app" }),
  ];
}

test("idle shutdown stops all modes and persists one reason-aware summary without triggering a turn", async () => {
  const h = makeHarness();
  const metas = launchAllModes(h);
  const { ctx, directAppends } = makeCtx({ idle: true });

  await h.pi.emit("session_shutdown", { type: "session_shutdown", reason: "reload" }, ctx);

  assert.equal(h.runtime.activeCount(), 0);
  const summaries = h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL);
  assert.equal(summaries.length, 1);
  const summary = summaries[0]!;
  assert.equal(summary.options?.triggerTurn, false);
  assert.match(summary.message.content, /\/reload stopped all background monitors/);
  assert.match(summary.message.content, /restarted manually/);
  assert.match(summary.message.content, /Stopped 3 monitor\(s\)/);
  for (const meta of metas) assert.ok(summary.message.content.includes(meta.id));
  // Idle path uses pi.sendMessage, not the direct session-manager append.
  assert.equal(directAppends.length, 0);
});

test("mid-stream shutdown appends the summary directly through the bound SessionManager", async () => {
  const h = makeHarness();
  launchAllModes(h);
  const { ctx, directAppends } = makeCtx({ idle: false });

  await h.pi.emit("session_shutdown", { type: "session_shutdown", reason: "quit" }, ctx);

  assert.equal(h.runtime.activeCount(), 0);
  // Nothing routed through the steer queue…
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL).length, 0);
  // …and exactly one entry written synchronously to the session.
  assert.equal(directAppends.length, 1);
  const entry = directAppends[0]!;
  assert.equal(entry.customType, MESSAGE_TYPE_STOP_ALL);
  assert.equal(entry.display, true);
  assert.match(entry.content, /pi quit and stopped all background monitors/);
});

test("mid-stream shutdown falls back to sendMessage when direct append is unavailable", async () => {
  const h = makeHarness();
  launchAllModes(h);
  const { ctx } = makeCtx({ idle: false, supportsDirectAppend: false });
  await h.pi.emit("session_shutdown", { type: "session_shutdown", reason: "new" }, ctx);
  const summaries = h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL);
  assert.equal(summaries.length, 1);
  assert.equal(summaries[0]!.options?.triggerTurn, false);
});

test("every shutdown reason names itself in the summary", async () => {
  for (const [reason, pattern] of [
    ["quit", /quit/],
    ["reload", /reload/],
    ["new", /new session/],
    ["resume", /resuming/],
    ["fork", /fork/],
  ] as const) {
    const h = makeHarness();
    h.runtime.launch({ command: "job" });
    const { ctx } = makeCtx({ idle: true });
    await h.pi.emit("session_shutdown", { type: "session_shutdown", reason }, ctx);
    const summary = h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL)[0]!;
    assert.match(summary.message.content, pattern, `reason ${reason}`);
  }
});

test("shutdown with no active watchers appends nothing", async () => {
  const h = makeHarness();
  const { ctx, directAppends } = makeCtx({ idle: true });
  await h.pi.emit("session_shutdown", { type: "session_shutdown", reason: "quit" }, ctx);
  assert.equal(h.pi.sent.length, 0);
  assert.equal(directAppends.length, 0);
});

test("quit shutdown SIGKILLs process groups immediately after SIGTERM (no timers left)", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "spawned" });
  const child = h.proc.lastChild();

  await h.pi.emit(
    "session_shutdown",
    { type: "session_shutdown", reason: "quit" },
    makeCtx({ idle: true }).ctx,
  );

  // Pi's process exits right after quit shutdown: the 3s escalation timer
  // would never fire, so SIGKILL must already have been sent.
  assert.deepEqual(h.proc.kills, [
    { pid: child.pid, group: true, signal: "SIGTERM" },
    { pid: child.pid, group: true, signal: "SIGKILL" },
  ]);
  assert.equal(h.clock.pendingCount(), 0, "no escalation timer is pending");
});

test("non-quit shutdown keeps the bounded SIGTERM→SIGKILL escalation", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "spawned" });
  const child = h.proc.lastChild();

  await h.pi.emit(
    "session_shutdown",
    { type: "session_shutdown", reason: "reload" },
    makeCtx({ idle: true }).ctx,
  );

  assert.deepEqual(h.proc.kills, [{ pid: child.pid, group: true, signal: "SIGTERM" }]);
  h.clock.advance(3000);
  assert.deepEqual(h.proc.kills[1], { pid: child.pid, group: true, signal: "SIGKILL" });
});

test("children killed by shutdown never produce a process-exit turn", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "spawned" });
  const child = h.proc.lastChild();
  await h.pi.emit(
    "session_shutdown",
    { type: "session_shutdown", reason: "quit" },
    makeCtx({ idle: true }).ctx,
  );
  const before = h.pi.sentOfType(MESSAGE_TYPE_EVENT).length;
  child.exit(null, "SIGTERM"); // the SIGTERM lands after teardown
  h.clock.advance(10_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, before);
});
