/**
 * Self-test for watcher accounting. Run: bun harness/accounting.selftest.ts
 */
import { createTracker } from "./accounting.ts";

let failures = 0;
function check(name: string, got: any, want: any) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) {
    failures++;
    console.log(`FAIL ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
  } else {
    console.log(`ok   ${name}`);
  }
}

const t = createTracker();

// 1. successful monitor start
t.handle({
  type: "tool_execution_end",
  toolName: "monitor",
  isError: false,
  result: { content: [{ type: "text", text: "Watcher abc123 running (mode=spawn). Will ping when: ready + exit." }] },
});
check("start -> active 1", t.activeWatchers(), 1);
check("starts", t.stats().watcherStarts, 1);

// 2. failed monitor start does not count
t.handle({
  type: "tool_execution_end",
  toolName: "monitor",
  isError: true,
  result: { content: [{ type: "text", text: "Error: watcher limit reached" }] },
});
check("failed start ignored", t.activeWatchers(), 1);

// 3. SKILL.md-style text read back as a tool result must NOT count (the historical bug)
t.handle({
  type: "message_start",
  message: { role: "toolResult", content: "docs say: [watcher <id>] then TIMEOUT after 65536 bytes and PROCESS EXITED" },
});
check("skill-text trap ignored", t.stats(), { watcherStarts: 1, watcherStops: 0, monitorEventPings: 0, stopAllSeen: false });

// 4. user text merely CONTAINING "[watcher " mid-sentence is not a ping
t.handle({
  type: "message_start",
  message: { role: "user", content: "as the docs note, a line like [watcher x] TIMEOUT after Ns is only an example" },
});
check("embedded mention ignored", t.stats().monitorEventPings, 0);

// 5. real injected death ping at line start
t.handle({
  type: "message_start",
  message: { role: "user", content: "[watcher abc123] PROCESS EXITED (code=0 signal=none)" },
});
check("death ping counted", t.stats().monitorEventPings, 1);
check("death stops watcher", t.activeWatchers(), 0);

// 6. poll watcher + kill
t.handle({
  type: "tool_execution_end",
  toolName: "monitor",
  isError: false,
  result: { content: [{ type: "text", text: "Watcher zzz9 polling. Will ping when: COMPLETE." }] },
});
check("poll start", t.activeWatchers(), 1);
t.handle({
  type: "tool_execution_end",
  toolName: "monitor_kill",
  isError: false,
  result: { content: [{ type: "text", text: "Stopped watcher zzz9." }] },
});
check("kill stops watcher", t.activeWatchers(), 0);

// 7. steered ping mid-stream
t.handle({
  type: "tool_execution_end",
  toolName: "monitor",
  isError: false,
  result: { content: [{ type: "text", text: "Watcher q1 running (mode=spawn)." }] },
});
t.handle({ type: "queue_update", steering: ["[watcher q1] matched: TRAINING COMPLETE saved"] });
check("steered ping counted", t.stats().monitorEventPings, 2);
check("non-death steer keeps watcher", t.activeWatchers(), 1);

// 8. kill-all (id "*") zeroes everything
t.handle({
  type: "tool_execution_start",
  toolName: "monitor_kill",
  args: { id: "*" },
});
t.handle({
  type: "tool_execution_end",
  toolName: "monitor_kill",
  isError: false,
  result: { content: [{ type: "text", text: "Stopped 3 background monitor(s)." }] },
});
check("kill-all zeroes", t.activeWatchers(), 0);

if (failures) {
  console.log(`\n${failures} FAILURES`);
  process.exit(1);
}
console.log("\nPASS: accounting self-test");
