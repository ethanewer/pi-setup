/**
 * Watcher accounting for monitor-bench.
 *
 * Pure logic over pi agent-session events; used by run-task.ts live and by
 * accounting.selftest.ts against synthetic event streams.
 *
 * Counting rules:
 *  - a successful `monitor` tool result ("Watcher <id> running|polling") starts one watcher
 *  - a successful `monitor_kill` stops as many as its result reports
 *  - `monitor_kill` with id "*" (or legacy `monitor_kill_all`) zeroes the count
 *  - an injected ping whose text starts with "[watcher " counts as a ping;
 *    death markers (PROCESS EXITED / SPAWN ERROR / TIMEOUT after) also stop one watcher
 *  - text merely *containing* "[watcher " (e.g. the SKILL.md docs read back as a
 *    tool result) must never count.
 */

export function textOf(content: any): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content.map((b: any) => (typeof b === "string" ? b : b?.text ?? "")).join("\n");
  }
  return "";
}

export const isWatcherPing = (text: string) => /^\[watcher /m.test(text);
export const isWatcherDeath = (text: string) =>
  /PROCESS EXITED|SPAWN ERROR|TIMEOUT after/.test(text);

export interface TrackerStats {
  watcherStarts: number;
  watcherStops: number;
  monitorEventPings: number;
  stopAllSeen: boolean;
}

export function createTracker() {
  let watcherStarts = 0;
  let watcherStops = 0;
  let monitorEventPings = 0;
  let stopAllSeen = false;

  const activeWatchers = () => (stopAllSeen ? 0 : Math.max(0, watcherStarts - watcherStops));

  function handle(event: any) {
    switch (event?.type) {
      case "tool_execution_start": {
        // kill-all is intentionally invoked as monitor_kill with id "*"
        if (event.toolName === "monitor_kill" && event.args?.id === "*") stopAllSeen = true;
        break;
      }
      case "tool_execution_end": {
        const text = textOf(event.result?.content ?? event.result);
        if (event.toolName === "monitor" && !event.isError && /Watcher \S+ (running|polling)/.test(text)) {
          watcherStarts++;
        } else if (event.toolName === "monitor_kill" && !event.isError) {
          watcherStops += (text.match(/Stopped watcher/g) ?? []).length || 1;
        } else if (event.toolName === "monitor_kill_all" && !event.isError) {
          stopAllSeen = true; // legacy transcripts (pre-merge)
        }
        break;
      }
      case "message_start": {
        const m = event.message;
        // injected pings arrive as user-visible messages; tool results and assistant
        // messages can quote watcher syntax (docs, reports) and must not count
        if (m && m.role !== "assistant" && m.role !== "toolResult") {
          const text = textOf(m.content);
          if (isWatcherPing(text)) {
            monitorEventPings++;
            if (isWatcherDeath(text)) watcherStops++;
          }
          if (/monitor-stop-all|Stopped all watchers/.test(text)) stopAllSeen = true;
        }
        break;
      }
      case "queue_update": {
        for (const text of event.steering ?? []) {
          if (isWatcherPing(text)) {
            monitorEventPings++;
            if (isWatcherDeath(text)) watcherStops++;
          }
        }
        break;
      }
    }
  }

  const stats = (): TrackerStats => ({ watcherStarts, watcherStops, monitorEventPings, stopAllSeen });

  return { handle, activeWatchers, stats };
}
