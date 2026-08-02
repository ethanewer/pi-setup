import { test } from "node:test";
import assert from "node:assert/strict";
import { makeHarness } from "./helpers.ts";
import { MAX_SPAWN_PENDING_BYTES, MESSAGE_TYPE_EVENT } from "../extensions/monitor/types.ts";
import { boundPartialLine } from "../extensions/monitor/text.ts";

// A watcher matches whole lines. A process that only ever rewrites one line with carriage
// returns therefore never matches anything, and before this it also grew an unbounded
// buffer while doing so. Silence was the real damage: an agent cannot tell a blind watcher
// from one whose job has not reached its marker yet, and waits on it forever.

const contents = (h: ReturnType<typeof makeHarness>): string[] =>
  h.pi.sentOfType(MESSAGE_TYPE_EVENT).map((s: { message?: { content?: string } }) => s.message?.content ?? "");
const warnings = (h: ReturnType<typeof makeHarness>): string[] =>
  contents(h).filter((c) => c.includes("NO LINE BREAK"));

test("a carriage-return progress bar warns exactly once, however long it runs", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "train", coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  // ~2 MB of redraws, no newline anywhere.
  for (let i = 0; i < 200; i++) child.pushStdout("\r" + "x".repeat(10_000));
  h.clock.advance(60_000);

  const warned = warnings(h);
  assert.equal(warned.length, 1, "exactly one warning for the life of the watcher");
  assert.match(warned[0]!, /NO LINE BREAK in 65536 bytes/);
  assert.match(warned[0]!, /progress bar/);
  assert.match(warned[0]!, /newline-terminated markers, or watch it with poll mode/);
});

test("ordinary newline output never warns and still matches", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "train", coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  for (let i = 0; i < 500; i++) child.pushStdout(`step ${i}\n`);
  child.pushStdout("error: diverged\n");
  h.clock.advance(60_000);

  assert.equal(warnings(h).length, 0);
  assert.ok(contents(h).some((c) => c.includes("error: diverged")), "the matching line still fires");
});

test("a marker printed after the bar still matches once its newline arrives", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "train", coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  // Overflow the buffer with redraws, then finish the line with a real marker.
  for (let i = 0; i < 20; i++) child.pushStdout("\r" + "x".repeat(10_000));
  child.pushStdout("\rEVAL_COMPLETE ok\n");
  h.clock.advance(60_000);

  assert.ok(
    contents(h).some((c) => c.includes("EVAL_COMPLETE ok")),
    "keeping the text after the final carriage return preserves the marker",
  );
});

test("output with no carriage return at all is still bounded", () => {
  const h = makeHarness();
  h.runtime.launch({ command: "train", coalesceSeconds: 0 });
  const child = h.proc.lastChild();
  for (let i = 0; i < 30; i++) child.pushStdout("y".repeat(10_000)); // 300 KB, one line
  h.clock.advance(60_000);

  assert.equal(warnings(h).length, 1);
  // The retained tail is what reaches the matcher when the process exits.
  child.exit(0, null);
  h.clock.advance(60_000);
  const longest = Math.max(...contents(h).map((c) => c.length));
  assert.ok(longest < 300_000, `emitted content stayed bounded, saw ${longest}`);
});

test("file mode is blind to the same output and warns the same way", () => {
  const h = makeHarness();
  h.files.set("/log/app", "");
  h.runtime.launch({ logFile: "/log/app", coalesceSeconds: 0 });
  for (let i = 0; i < 20; i++) h.files.append("/log/app", "\r" + "x".repeat(10_000));
  h.clock.advance(60_000);

  assert.equal(warnings(h).length, 1);
});

test("boundPartialLine leaves anything under the cap byte-for-byte alone", () => {
  // Ordinary output must reach the matcher unchanged; only an implausibly long partial
  // line gets rewritten.
  const line = "a\rb\rc: still one real line";
  assert.equal(boundPartialLine(line, MAX_SPAWN_PENDING_BYTES), line);

  const over = "head\r" + "z".repeat(MAX_SPAWN_PENDING_BYTES);
  const bounded = boundPartialLine(over, MAX_SPAWN_PENDING_BYTES);
  assert.ok(!bounded.includes("head"), "past the cap the pre-redraw text is dropped");
  assert.ok(Buffer.byteLength(bounded, "utf8") <= MAX_SPAWN_PENDING_BYTES);

  // No carriage return to cut at: fall back to a byte tail, and never split a character.
  const wide = "é".repeat(MAX_SPAWN_PENDING_BYTES);
  const tail = boundPartialLine(wide, MAX_SPAWN_PENDING_BYTES);
  assert.ok(Buffer.byteLength(tail, "utf8") <= MAX_SPAWN_PENDING_BYTES);
  assert.ok(!tail.includes("�"), "no replacement characters from a mid-character cut");
});
