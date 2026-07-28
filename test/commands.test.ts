import { test } from "node:test";
import assert from "node:assert/strict";
import { makeCtx, makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT, MESSAGE_TYPE_STOP_ALL } from "../extensions/monitor/types.ts";

// ---- /monitor argument parsing ---------------------------------------------

test("a plain /monitor command containing ' -- ' is preserved verbatim", async () => {
  const h = makeHarness();
  await h.pi.command("monitor").handler("git log --oneline -- src/main.ts", makeCtx().ctx);
  assert.equal(h.proc.spawned.length, 1);
  assert.equal(h.proc.spawned[0]!.command, "git log --oneline -- src/main.ts");
});

test("monitor flags with a ' -- ' separator take the command after the separator", async () => {
  const h = makeHarness();
  await h.pi.command("monitor").handler("--poll --every 5 -- ssh box 'tail -n5 log'", makeCtx().ctx);
  assert.equal(h.proc.spawned.length, 1);
  assert.equal(h.proc.spawned[0]!.command, "ssh box 'tail -n5 log'");
  // Poll cadence honors --every.
  h.proc.lastChild().exit(0);
  h.clock.advance(5000);
  assert.equal(h.proc.spawned.length, 2);
});

test("monitor flags without a separator are stripped from the command", async () => {
  const h = makeHarness();
  await h.pi.command("monitor").handler("--poll --every 30 tail -f /var/log/app", makeCtx().ctx);
  assert.equal(h.proc.spawned.length, 1);
  assert.equal(h.proc.spawned[0]!.command, "tail -f /var/log/app");
});

test("--timeout with a ' -- ' separator keeps the command intact and arms the timeout", async () => {
  const h = makeHarness();
  await h.pi.command("monitor").handler("--timeout 60 -- run.sh -- --flag", makeCtx().ctx);
  assert.equal(h.proc.spawned[0]!.command, "run.sh -- --flag");
  h.clock.advance(60_000);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /TIMEOUT after 60s/);
});

test("/monitor --file still launches a file watcher", async () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  const { ctx, notices } = makeCtx();
  await h.pi.command("monitor").handler("--file /log/app", ctx);
  assert.equal(h.runtime.activeCount(), 1);
  assert.equal(h.runtime.list()[0]!.mode, "file");
  assert.equal(notices.length, 1);
  assert.match(notices[0]!.message, /running \(file\)/);
});

// ---- hasUI=false (headless/print mode) --------------------------------------

test("/monitor works headless: watcher starts, ui.notify is never touched", async () => {
  const h = makeHarness();
  const { ctx, notices } = makeCtx({ hasUI: false });
  await h.pi.command("monitor").handler("long-job.sh", ctx);
  assert.equal(h.runtime.activeCount(), 1);
  assert.equal(h.proc.spawned[0]!.command, "long-job.sh");
  assert.equal(notices.length, 0);
});

test("/monitor with no args is a no-op headless (usage goes nowhere, no crash)", async () => {
  const h = makeHarness();
  const { ctx, notices } = makeCtx({ hasUI: false });
  await h.pi.command("monitor").handler("", ctx);
  assert.equal(h.runtime.activeCount(), 0);
  assert.equal(notices.length, 0);
});

test("/monitors and /monitor-kill work headless", async () => {
  const h = makeHarness();
  const meta = h.runtime.launch({ command: "job" });
  const { ctx, notices } = makeCtx({ hasUI: false });
  await h.pi.command("monitors").handler("", ctx);
  await h.pi.command("monitor-kill").handler(meta.id, ctx);
  assert.equal(h.runtime.activeCount(), 0, "watcher was stopped");
  assert.equal(notices.length, 0);
});

test("/monitor-kill-all headless still appends the consolidated context message", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "job-a" });
  h.runtime.launch({ command: "job-b" });
  const { ctx, notices } = makeCtx({ hasUI: false });
  await h.pi.command("monitor-kill-all").handler("", ctx);
  assert.equal(h.runtime.activeCount(), 0);
  assert.equal(notices.length, 0);
  const summaries = h.pi.sentOfType(MESSAGE_TYPE_STOP_ALL);
  assert.equal(summaries.length, 1);
  assert.equal(summaries[0]!.options?.triggerTurn, false);
  assert.match(summaries[0]!.message.content, /Stopped 2 background monitor\(s\)/);
});

test("the 17th watcher headless is refused without touching the UI", async () => {
  const h = makeHarness();
  for (let i = 0; i < 16; i++) h.runtime.launch({ command: `job-${i}` });
  const { ctx, notices } = makeCtx({ hasUI: false });
  await h.pi.command("monitor").handler("one-too-many", ctx);
  assert.equal(h.runtime.activeCount(), 16);
  assert.equal(notices.length, 0);
});
