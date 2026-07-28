import { test } from "node:test";
import assert from "node:assert/strict";
import { makeCtx, makeHarness } from "./helpers.ts";
import {
  LEGACY_WATCHER_ENTRY_TYPE,
  MESSAGE_TYPE_NOTE,
} from "../extensions/monitor/types.ts";

test("watcher definitions are never persisted via appendEntry", async () => {
  const h = makeHarness();
  h.runtime.launch({ command: "spawned" });
  h.runtime.launch({ command: "polled", intervalSeconds: 30, heartbeatMinutes: 5 });
  h.runtime.launch({ logFile: "/log/x", timeoutSeconds: 60 });
  assert.deepEqual(h.pi.appendedEntries, []);
});

test("session_start never restores watchers, even with legacy monitor-watcher entries", async () => {
  const h = makeHarness();
  const legacyEntries = [
    {
      type: "custom",
      customType: LEGACY_WATCHER_ENTRY_TYPE,
      data: { command: "ssh box 'tail log'", intervalSec: 30, cwd: "/tmp" },
    },
    {
      type: "custom",
      customType: LEGACY_WATCHER_ENTRY_TYPE,
      data: { logFile: "/var/log/train.log", cwd: "/tmp" },
    },
  ];
  for (const reason of ["startup", "reload", "new", "resume"]) {
    const { ctx } = makeCtx({ entries: legacyEntries });
    await h.pi.emit("session_start", { type: "session_start", reason }, ctx);
  }
  assert.equal(h.runtime.activeCount(), 0);
  assert.equal(h.proc.spawned.length, 0);
  assert.equal(h.pi.sent.length, 0);
  assert.equal(h.pi.appendedEntries.length, 0);
});

test("repeated reload/resume cycles never create watchers or notes", async () => {
  const h = makeHarness();
  for (let i = 0; i < 5; i++) {
    await h.pi.emit("session_start", { type: "session_start", reason: "reload" }, makeCtx().ctx);
    await h.pi.emit("session_start", { type: "session_start", reason: "resume" }, makeCtx().ctx);
  }
  assert.equal(h.runtime.activeCount(), 0);
  assert.equal(h.pi.sent.length, 0);
});

test("fork startup receives exactly one no-turn source-monitor note", async () => {
  const h = makeHarness();
  await h.pi.emit(
    "session_start",
    { type: "session_start", reason: "fork", previousSessionFile: "/s/prev.jsonl" },
    makeCtx().ctx,
  );
  const notes = h.pi.sentOfType(MESSAGE_TYPE_NOTE);
  assert.equal(notes.length, 1);
  assert.equal(notes[0]!.options?.triggerTurn, false);
  assert.match(notes[0]!.message.content, /not carried into the fork/);
  // Non-fork startups add nothing.
  await h.pi.emit("session_start", { type: "session_start", reason: "startup" }, makeCtx().ctx);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_NOTE).length, 1);
});
