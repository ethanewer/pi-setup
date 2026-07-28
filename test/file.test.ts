import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";

test("file mode pushes matching appended lines after the debounce window", () => {
  const h = makeHarness();
  h.files.set("/log/train", "old line with error\n"); // pre-existing content is skipped
  h.runtime.launch({ logFile: "/log/train", coalesceSeconds: 0 });

  h.files.append("/log/train", "loss improving\nerror: NaN detected\n");
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0, "debounce still pending");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error: NaN detected/);
  assert.equal(events[0]!.message.content.includes("old line"), false);
});

test("file truncation/rotation resets the read offset", () => {
  const h = makeHarness();
  h.files.set("/log/app", "aaaaaaaaaaaaaaaaaaaaaaaaaaaa\n");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0 });

  h.files.set("/log/app", "error after rotate\n"); // shorter: rotated
  h.files.notify("/log/app");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error after rotate/);
});

test("the 5s backstop poll catches appends when fs.watch is unavailable", () => {
  const h = makeHarness();
  h.files.watchSupported = false;
  h.files.set("/log/app", "");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0 });
  h.files.append("/log/app", "fatal: crashed\n"); // no watch event fires
  h.clock.advance(4999);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
  h.clock.advance(5001);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /fatal: crashed/);
});

test("a file that appears later is picked up from offset zero", () => {
  const h = makeHarness();
  h.runtime.launch({ logFile: "/log/late", coalesceSeconds: 0 });
  h.clock.advance(10_000); // backstop ticks against a missing file: no crash
  h.files.set("/log/late", "error: born failing\n");
  h.clock.advance(5000);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error: born failing/);
});

test("stopping a file watcher closes the fs watcher and the backstop", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  const meta = h.runtime.launch({ logFile: "/log/app" });
  assert.equal(h.files.watcherCount("/log/app"), 1);
  h.runtime.stop(meta.id);
  assert.equal(h.files.watcherCount("/log/app"), 0);
  assert.equal(h.clock.pendingCount(), 0);
  h.files.append("/log/app", "error: unseen\n");
  h.clock.advance(60_000);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0);
});
