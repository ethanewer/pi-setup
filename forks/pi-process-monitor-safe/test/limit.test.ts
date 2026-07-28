import { test } from "node:test";
import assert from "node:assert/strict";
import { makeCtx, makeHarness, launchViaTool } from "./helpers.ts";
import { MAX_ACTIVE_WATCHERS, MonitorLimitError } from "../extensions/monitor/types.ts";

const LIMIT_MESSAGE =
  "16 active monitors; use monitor_status, then monitor_kill (or monitor_kill_all) before starting another.";

test("the 16th monitor starts and the 17th is refused via the tool with an actionable error", async () => {
  const h = makeHarness();
  for (let i = 0; i < MAX_ACTIVE_WATCHERS; i++) {
    await launchViaTool(h, { command: `job-${i}` });
  }
  assert.equal(h.runtime.activeCount(), 16);

  await assert.rejects(
    h.pi.tool("monitor").execute("t17", { command: "one-too-many" }, undefined, undefined, makeCtx().ctx),
    (error: unknown) => {
      assert.ok(error instanceof MonitorLimitError);
      assert.equal((error as Error).message, LIMIT_MESSAGE);
      return true;
    },
  );
  // Refused before any resource was created: no 17th child was spawned.
  assert.equal(h.proc.spawned.length, 16);
  assert.equal(h.runtime.activeCount(), 16);
});

test("the 17th monitor via /monitor shows the same limit message as a UI warning", async () => {
  const h = makeHarness();
  for (let i = 0; i < MAX_ACTIVE_WATCHERS; i++) {
    h.runtime.launch({ command: `job-${i}` });
  }
  const { ctx, notices } = makeCtx();
  await h.pi.command("monitor").handler("echo overflow", ctx);
  assert.equal(notices.length, 1);
  assert.equal(notices[0]!.level, "warning");
  assert.equal(notices[0]!.message, LIMIT_MESSAGE);
  assert.equal(h.runtime.activeCount(), 16);
});

test("stopping a watcher releases its slot immediately (no SIGKILL wait)", async () => {
  const h = makeHarness();
  const metas = [];
  for (let i = 0; i < MAX_ACTIVE_WATCHERS; i++) {
    metas.push(h.runtime.launch({ command: `job-${i}` }));
  }
  assert.throws(() => h.runtime.launch({ command: "blocked" }), MonitorLimitError);

  h.runtime.stop(metas[0]!.id);
  // The killed child has NOT exited yet, but the slot is already free.
  assert.equal(h.proc.spawned[0]!.child.hasExited, false);
  assert.equal(h.runtime.activeCount(), 15);
  const replacement = h.runtime.launch({ command: "replacement" });
  assert.ok(replacement.id);
  assert.equal(h.runtime.activeCount(), 16);
});

test("a natural spawn exit releases its slot", async () => {
  const h = makeHarness();
  for (let i = 0; i < MAX_ACTIVE_WATCHERS; i++) {
    h.runtime.launch({ command: `job-${i}` });
  }
  h.proc.spawned[3]!.child.exit(0);
  assert.equal(h.runtime.activeCount(), 15);
  assert.doesNotThrow(() => h.runtime.launch({ command: "fits-now" }));
});

test("monitor tool without a source throws (isError path)", async () => {
  const h = makeHarness();
  await assert.rejects(
    h.pi.tool("monitor").execute("t1", {}, undefined, undefined, makeCtx().ctx),
    /provide `command` and\/or `logFile`/,
  );
});

test("status lists only active watchers", async () => {
  const h = makeHarness();
  const a = h.runtime.launch({ command: "a" });
  const b = h.runtime.launch({ command: "b" });
  h.runtime.stop(a.id);
  const result = await h.pi.tool("monitor_status").execute("t1", {}, undefined, undefined, makeCtx().ctx);
  assert.deepEqual(
    result.details.watchers.map((w: { id: string }) => w.id),
    [b.id],
  );
});
