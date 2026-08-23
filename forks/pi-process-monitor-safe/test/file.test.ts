import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";

test("relative logFile resolves against the watcher cwd", () => {
  const h = makeHarness();
  h.files.set("/work/batch.log", "start\n"); // pre-existing content is skipped
  h.runtime.launch({ logFile: "batch.log", cwd: "/work", coalesceSeconds: 0 });

  h.files.append("/work/batch.log", "BATCH FINISHED rc=0\n");
  h.files.notify("/work/batch.log");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /BATCH FINISHED/);
});

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

test("file mode buffers a partial trailing line across reads until its newline arrives", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0 });

  h.files.append("/log/app", "error: half");
  h.clock.advance(150);
  assert.equal(h.pi.sentOfType(MESSAGE_TYPE_EVENT).length, 0, "unterminated line is held");

  h.files.append("/log/app", " now whole\nplain noise\n");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error: half now whole/);
});

test("file rotation discards the held partial line", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0 });
  h.files.append("/log/app", "error: doomed partial"); // no newline before rotation
  h.clock.advance(150);
  h.files.set("/log/app", "quiet\n"); // shorter: rotated
  h.files.notify("/log/app");
  h.clock.advance(150);
  h.files.append("/log/app", "error: fresh\n");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.match(events[0]!.message.content, /error: fresh/);
  assert.equal(events[0]!.message.content.includes("doomed"), false);
});

test("a huge append is read bounded: content past the read cap is skipped to the tail", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0, notifyOn: ["error"] });
  // ~288 KiB in one burst exceeds the 256 KiB per-read cap.
  const filler = ("f".repeat(127) + "\n").repeat(2304);
  h.files.append("/log/app", "error head\n" + filler + "error tail\n");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 1);
  assert.equal(events[0]!.message.content.includes("error head"), false, "head beyond the cap dropped");
  assert.match(events[0]!.message.content, /error tail/);
});

test("an oversized unterminated line retains only a bounded tail, and says so once", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0, notifyOn: ["error"] });
  h.files.append("/log/app", "HEADMARK " + "x".repeat(100_000)); // > 64 KiB pending cap, no newline
  h.clock.advance(150);
  // This used to emit nothing at all, which is exactly the problem: a watcher reading a
  // log that never breaks a line is blind, and silence is indistinguishable from waiting.
  const afterOverflow = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(afterOverflow.length, 1);
  assert.match(afterOverflow[0]!.message.content, /NO LINE BREAK/);

  h.files.append("/log/app", " error at the end\n");
  h.clock.advance(150);
  const events = h.pi.sentOfType(MESSAGE_TYPE_EVENT);
  assert.equal(events.length, 2, "the warning, then the real match");
  assert.match(events[1]!.message.content, /error at the end/);
  assert.equal(events[1]!.message.content.includes("HEADMARK"), false);
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
