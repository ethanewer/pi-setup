import { test } from "node:test";
import assert from "node:assert/strict";
import { makeCtx, makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_STOP_ALL } from "../extensions/monitor/types.ts";

test("/monitor-kill-all stops everything, notifies per watcher, and appends exactly one consolidated no-turn message", async () => {
  const h = makeHarness();
  const a = h.runtime.launch({ command: "job-a", label: "alpha" });
  const b = h.runtime.launch({ logFile: "/log/b" });
  const c = h.runtime.launch({ command: "job-c", intervalSeconds: 30 });

  const { ctx, notices } = makeCtx();
  await h.pi.command("monitor-kill-all").handler("", ctx);

  assert.equal(h.runtime.activeCount(), 0);
  // One UI notification per stopped watcher.
  assert.equal(notices.length, 3);
  for (const meta of [a, b, c]) {
    assert.ok(notices.some((n) => n.message.includes(meta.id) && n.level === "info"));
  }
  // Exactly one consolidated model-context message, no model turn.
  const summaries = h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL);
  assert.equal(summaries.length, 1);
  const summary = summaries[0]!;
  assert.equal(summary.options?.triggerTurn, false);
  assert.match(summary.message.content, /Stopped 3 background monitor\(s\)/);
  for (const meta of [a, b, c]) {
    assert.ok(summary.message.content.includes(meta.id));
  }
});

test("/monitor-kill-all is idempotent and reports empty state without a model-context message", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "job" });

  const first = makeCtx();
  await h.pi.command("monitor-kill-all").handler("", first.ctx);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL).length, 1);

  const second = makeCtx();
  await h.pi.command("monitor-kill-all").handler("", second.ctx);
  assert.equal(second.notices.length, 1);
  assert.match(second.notices[0]!.message, /No active monitors/);
  // Still only the first summary: empty kill-all adds nothing to context.
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL).length, 1);
});

test("monitor_kill id=\"*\" returns the consolidated list in the tool result without a duplicate custom message", async () => {
  const h = makeHarness();
  const a = h.runtime.launch({ command: "job-a" });
  const b = h.runtime.launch({ command: "job-b" });

  const result = await h.pi
    .tool("monitor_kill")
    .execute("t1", { id: "*" }, undefined, undefined, makeCtx().ctx);
  assert.equal(h.runtime.activeCount(), 0);
  assert.match(result.content[0]!.text, /Stopped 2 background monitor\(s\)/);
  assert.ok(result.content[0]!.text.includes(a.id));
  assert.ok(result.content[0]!.text.includes(b.id));
  assert.deepEqual(
    result.details.watchers.map((w: { id: string }) => w.id).sort(),
    [a.id, b.id].sort(),
  );
  // Tool results are already model context: no extra custom message.
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL).length, 0);
});

test("monitor_kill id=\"*\" with no active watchers reports that fact plainly", async () => {
  const h = makeHarness();
  const result = await h.pi
    .tool("monitor_kill")
    .execute("t1", { id: "*" }, undefined, undefined, makeCtx().ctx);
  assert.equal(result.content[0]!.text, "No active monitors.");
  assert.deepEqual(result.details.watchers, []);
  assert.equal(h.pi.sent.length, 0);
});

test("kill-all terminates in-flight children by process group", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "spawned" });
  h.runtime.launch({ command: "polled", intervalSeconds: 30 });
  await h.pi.command("monitor-kill-all").handler("", makeCtx().ctx);
  const termKills = h.proc.kills.filter((k) => k.signal === "SIGTERM" && k.group);
  assert.equal(termKills.length, 2);
});
