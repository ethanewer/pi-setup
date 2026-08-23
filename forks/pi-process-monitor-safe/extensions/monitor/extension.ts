/**
 * Extension wiring for pi-process-monitor-safe: registers the monitor tools,
 * slash commands, message renderers, and session lifecycle handlers on top of
 * the injected-adapter runtime.
 *
 * Registers:
 *   tools:    monitor, monitor_status, monitor_kill (id "*" = all)
 *   commands: /monitor, /monitors, /monitor-kill, /monitor-kill-all
 *
 * Context semantics (see PLAN.md):
 *   - matched lines / natural exits / timeouts / heartbeat aggregates emit
 *     custom messages with triggerTurn: true;
 *   - /monitor-kill-all and session_shutdown summaries are model-visible but
 *     never trigger a turn;
 *   - watcher definitions are never persisted and never restored.
 */

import { Type, type Static } from "typebox";
import { Text, type AutocompleteItem } from "@earendil-works/pi-tui";
import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { createMonitorRuntime } from "./runtime.ts";
import {
  type Clock,
  type FileAdapter,
  MESSAGE_TYPE_EVENT,
  MESSAGE_TYPE_HEARTBEAT,
  MESSAGE_TYPE_NOTE,
  MESSAGE_TYPE_STOP_ALL,
  MAX_ACTIVE_WATCHERS,
  MonitorLimitError,
  type MonitorRuntime,
  type ProcessAdapter,
  type WatcherMeta,
} from "./types.ts";

export interface MonitorAdapters {
  clock: Clock;
  proc: ProcessAdapter;
  files: FileAdapter;
  randomId(): string;
  defaultCwd(): string;
}

type TextBlock = { type: "text"; text: string };

const text = (t: string): TextBlock[] => [{ type: "text", text: t }];

const metaLine = (m: WatcherMeta): string =>
  `- ${m.id}${m.label ? " · " + m.label : ""} [${m.mode}] events=${m.eventCount} last=${m.lastEventAt ?? "never"}`;

/** Consolidated stop list shared by monitor_kill_all and /monitor-kill-all. */
export function buildStopAllSummary(stopped: WatcherMeta[]): string {
  return [
    `[monitor] Stopped ${stopped.length} background monitor(s):`,
    ...stopped.map(metaLine),
    "Monitor definitions are never persisted; restart any monitor you still need.",
  ].join("\n");
}

const SHUTDOWN_LEADS: Record<string, string> = {
  quit: "pi quit and stopped all background monitors",
  reload: "/reload stopped all background monitors; they are not reloaded and must be restarted manually",
  new: "starting a new session stopped all background monitors of this session",
  resume: "resuming a different session stopped all background monitors of this session",
  fork: "forking stopped all background monitors of the source session",
};

/** Reason-aware summary persisted from session_shutdown. */
export function buildShutdownSummary(reason: string, stopped: WatcherMeta[]): string {
  const lead = SHUTDOWN_LEADS[reason] ?? `session shutdown (${reason}) stopped all background monitors`;
  return [
    `[monitor] ${lead}. Stopped ${stopped.length} monitor(s):`,
    ...stopped.map(metaLine),
    "These watchers no longer exist. Monitor definitions are never persisted, so nothing restarts automatically; recreate any monitor that is still needed.",
  ].join("\n");
}

export const FORK_NOTE =
  "[monitor] This session was created by forking; background monitors from the " +
  "source session were not carried into the fork. Start new monitors if they are still needed.";

/** Narrow structural view of the write-capable SessionManager methods. */
interface CustomMessageAppender {
  appendCustomMessageEntry(
    customType: string,
    content: string,
    display: boolean,
    details?: unknown,
  ): string;
}

/**
 * Persist a model-visible, non-turn-triggering custom message.
 *
 * Idle: pi.sendMessage without triggerTurn appends immediately. Streaming:
 * pi.sendMessage would park the message in the steer queue, which is torn
 * down with the session — so write the entry synchronously through the bound
 * SessionManager instead. Shutdown must never wake the model either way.
 */
function persistNoTurnMessage(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  customType: string,
  content: string,
  details: unknown,
): void {
  if (!ctx.isIdle()) {
    const sm = ctx.sessionManager as unknown as Partial<CustomMessageAppender>;
    if (typeof sm.appendCustomMessageEntry === "function") {
      sm.appendCustomMessageEntry(customType, content, true, details);
      return;
    }
  }
  pi.sendMessage(
    { customType, content, display: true, details },
    { triggerTurn: false, deliverAs: "steer" },
  );
}

const notify = (
  ctx: ExtensionContext | ExtensionCommandContext,
  message: string,
  level: "info" | "warning" | "error",
): void => {
  if (ctx.hasUI) ctx.ui.notify(message, level);
};

export function registerMonitorExtension(
  pi: ExtensionAPI,
  adapters: MonitorAdapters,
): MonitorRuntime {
  const runtime = createMonitorRuntime({
    ...adapters,
    send: (message, options) => pi.sendMessage(message, options),
  });

  // ---- session lifecycle -------------------------------------------------
  // No restore path: watcher definitions are never persisted, and legacy
  // upstream "monitor-watcher" entries in old sessions are deliberately
  // ignored. The only session_start injection is the fork note below (Pi
  // creates the fork before shutting down the source session, so the fork's
  // transcript would otherwise imply the source's monitors still run).
  pi.on("session_start", async (event, _ctx) => {
    if (event.reason !== "fork") return;
    pi.sendMessage(
      {
        customType: MESSAGE_TYPE_NOTE,
        content: FORK_NOTE,
        display: true,
        details: { reason: "fork" },
      },
      { triggerTurn: false, deliverAs: "steer" },
    );
  });

  pi.on("session_shutdown", async (event, ctx) => {
    // On quit the Pi process exits immediately, so the 3s SIGKILL escalation
    // timer would never fire; SIGKILL the process groups right away instead.
    // Every other stop path keeps the bounded escalation.
    const stopped = runtime.stopAll({ immediateKill: event.reason === "quit" });
    if (!stopped.length) return;
    persistNoTurnMessage(
      pi,
      ctx,
      MESSAGE_TYPE_STOP_ALL,
      buildShutdownSummary(event.reason, stopped),
      { reason: event.reason, watchers: stopped },
    );
  });

  // ---- rendering -----------------------------------------------------------
  pi.registerMessageRenderer(MESSAGE_TYPE_EVENT, (message, _opts, theme) => {
    const body =
      typeof message.content === "string" ? message.content : JSON.stringify(message.content);
    const m = /^\[watcher ([^ \]]+)(?: · ([^\]]+))?\] ([\s\S]*)$/.exec(body);
    if (m) {
      return new Text(
        theme.fg("accent", `[watcher ${m[1]}`) +
          (m[2] ? theme.fg("muted", ` · ${m[2]}`) : "") +
          theme.fg("accent", "] ") +
          theme.fg("dim", m[3] ?? ""),
        0,
        0,
      );
    }
    return new Text(theme.fg("accent", body), 0, 0);
  });
  for (const customType of [MESSAGE_TYPE_HEARTBEAT, MESSAGE_TYPE_STOP_ALL, MESSAGE_TYPE_NOTE]) {
    pi.registerMessageRenderer(customType, (message, _opts, theme) => {
      const body =
        typeof message.content === "string" ? message.content : JSON.stringify(message.content);
      const [head, ...rest] = body.split("\n");
      return new Text(
        theme.fg("accent", head ?? "") + (rest.length ? "\n" + theme.fg("dim", rest.join("\n")) : ""),
        0,
        0,
      );
    });
  }

  // ---- TOOL: monitor -------------------------------------------------------
  const monitorParams = Type.Object({
    command: Type.Optional(Type.String({ description: "Shell command. Spawned once & tailed (spawn); if intervalSeconds is also set, re-run every N s (poll, e.g. ssh h100 'tail -n5 log; pgrep -fc train')." })),
    intervalSeconds: Type.Optional(Type.Number({ description: "Poll interval in seconds. If set, `command` is re-run on this cadence (poll mode)." })),
    logFile: Type.Optional(Type.String({ description: "Path to a log file to tail for appended lines (file mode)." })),
    notifyOn: Type.Optional(Type.Array(Type.String(), { description: "Case-insensitive regexes. A line matching ANY is pushed. Defaults to milestones+failures (saved, complete, done, error, fail, oom, killed, traceback, …)." })),
    label: Type.Optional(Type.String({ description: "Human label for the watcher." })),
    cwd: Type.Optional(Type.String({ description: "Working directory for spawn/poll. Default current." })),
  });
  type MonitorParams = Static<typeof monitorParams>;

  pi.registerTool({
    name: "monitor",
    label: "Monitor",
    description:
      "Start a NON-BLOCKING background watcher over a process, a polling command (e.g. SSH), or a log file. " +
      "Returns immediately with a watcher id. The session is pinged (and woken if idle) when a line matches notifyOn " +
      "or the process exits/fails. Pick ONE source: `command` (spawn once; add `intervalSeconds` to poll on a cadence) " +
      "or `logFile` (tail appended lines). Stop watchers with monitor_kill (id \"*\" stops all).",
    promptSnippet:
      "Watch a background process/SSH/log and ping the session on milestones or failure",
    promptGuidelines: [
      "If a job may run longer than ~30 seconds (builds, tests, training, dev servers, migrations, remote SSH), run it under monitor instead of blocking bash: it returns at once and pings the session on milestones or failure. After starting a watcher, end your turn or do other work — never sleep or poll while one is running.",
    ],
    parameters: monitorParams,
    async execute(
      _id,
      params: MonitorParams,
      _signal,
      _onUpdate,
      ctx,
    ): Promise<{ content: TextBlock[]; details: { watcher: WatcherMeta } }> {
      // launch() throws MonitorLimitError at the cap; Pi surfaces the thrown
      // error to the model as an isError tool result with actionable text.
      const watcher = runtime.launch({
        command: params.command,
        intervalSeconds: params.intervalSeconds,
        logFile: params.logFile,
        notifyOn: params.notifyOn,
        heartbeatMinutes: params.heartbeatMinutes,
        label: params.label,
        coalesceSeconds: params.coalesceSeconds,
        maxLines: params.maxLines,
        cwd: params.cwd ?? ctx.cwd,
        timeoutSeconds: params.timeoutSeconds,
      });
      return {
        content: text(
          `Watcher ${watcher.id} running (mode=${watcher.mode}). Will ping when: ${watcher.watchingFor}. ` +
          `End your turn now; the ping will wake you. Do not sleep, poll, or re-check the job.`,
        ),
        details: { watcher },
      };
    },
  });

  // ---- TOOL: monitor_status --------------------------------------------------
  pi.registerTool({
    name: "monitor_status",
    label: "Monitor status",
    description: "List active background watchers with last-event time and event count.",
    parameters: Type.Object({}),
    async execute(): Promise<{ content: TextBlock[]; details: { watchers: WatcherMeta[] } }> {
      const list = runtime.list();
      if (!list.length) {
        return { content: text("No active monitors."), details: { watchers: [] } };
      }
      const lines = list.map(
        (m) =>
          `- ${m.id}${m.label ? " · " + m.label : ""} [${m.mode}] alive=${m.alive} events=${m.eventCount} last=${m.lastEventAt ?? "never"} watching: ${m.watchingFor}`,
      );
      return { content: text(lines.join("\n")), details: { watchers: list } };
    },
  });

  // ---- TOOL: monitor_kill -----------------------------------------------------
  pi.registerTool({
    name: "monitor_kill",
    label: "Monitor kill",
    description:
      "Stop a background watcher by id; use id \"*\" to stop ALL active watchers. " +
      "For spawn/poll children, signals the process group with SIGTERM, then SIGKILL after 3s.",
    parameters: Type.Object({ id: Type.String({ description: "Watcher id from monitor, or \"*\" for all." }) }),
    async execute(
      _id,
      params,
    ): Promise<{ content: TextBlock[]; details: { watcher?: WatcherMeta; watchers?: WatcherMeta[] } }> {
      if (params.id === "*") {
        const stopped = runtime.stopAll();
        if (!stopped.length) {
          return { content: text("No active monitors."), details: { watchers: [] } };
        }
        // The consolidated list lives in this tool result (already model
        // context); no duplicate custom message is appended.
        return { content: text(buildStopAllSummary(stopped)), details: { watchers: stopped } };
      }
      const watcher = runtime.stop(params.id);
      if (!watcher) {
        return { content: text(`No watcher ${params.id}.`), details: { watcher: undefined } };
      }
      return { content: text(`Stopped ${watcher.id}.`), details: { watcher } };
    },
  });

  // ---- COMMANDS (human-facing, with autocomplete) ----------------------------
  // /monitor <command...>            spawn watcher over the command
  // /monitor --poll --every 30 -- <cmd>   poll mode
  // /monitor --file <path>           file mode
  // /monitors                        list watchers
  // /monitor-kill <id>               stop one (autocompletes live ids)
  // /monitor-kill-all                stop everything
  pi.registerCommand("monitor", {
    description:
      "Start a background watcher over a command (default), or use --poll/--every/--file flags. Example: /monitor ssh h100 'tail -n5 log; pgrep -fc train'",
    handler: async (args, ctx) => {
      const a = args.trim();
      if (!a) {
        notify(ctx, "Usage: /monitor <command...>   (or /monitor --file <path>, /monitor --poll --every 30 -- <cmd>)", "info");
        return;
      }
      const isFile = /(^|\s)--file(\s|$)/.test(a);
      const every = /--every\s+(\d+)/.exec(a);
      // A bare --every implies poll mode: a cadence only makes sense for
      // polling, and silently spawning once instead would surprise the user.
      const isPoll = !isFile && (/(^|\s)--poll(\s|$)/.test(a) || every !== null);
      const timeout = /--timeout\s+(\d+)/.exec(a);
      const hasMonitorFlags = isPoll || isFile || every !== null || timeout !== null;
      // The " -- " separator only means anything when monitor flags precede
      // it; a plain command keeps every " -- " it contains verbatim
      // (e.g. `/monitor git log -- path`).
      let command: string;
      if (!hasMonitorFlags) {
        command = a.replace(/^--\s+/, "").trim();
      } else if (a.includes(" -- ")) {
        command = a.slice(a.indexOf(" -- ") + 4).trim();
      } else {
        command = a
          .replace(/(^|\s)--file\s+\S+/g, " ")
          .replace(/(^|\s)--poll(?=\s|$)/g, " ")
          .replace(/(^|\s)--every\s+\d+/g, " ")
          .replace(/(^|\s)--timeout\s+\d+/g, " ")
          .trim();
      }
      const timeoutSeconds = timeout ? Number(timeout[1]) : undefined;

      let watcher: WatcherMeta;
      try {
        if (isFile) {
          const logFile = (/--file\s+(\S+)/.exec(a)?.[1] ?? command).trim();
          if (!logFile) {
            notify(ctx, "Usage: /monitor --file <path>", "warning");
            return;
          }
          watcher = runtime.launch({ logFile, label: logFile.split("/").pop(), timeoutSeconds });
        } else if (isPoll) {
          if (!command) {
            notify(ctx, "Usage: /monitor --poll --every 30 -- <command>", "warning");
            return;
          }
          watcher = runtime.launch({
            command,
            intervalSeconds: every ? Number(every[1]) : 30,
            label: command.split(/\s+/).slice(0, 2).join(" "),
            timeoutSeconds,
          });
        } else {
          if (!command) {
            notify(ctx, "Usage: /monitor <command...>", "warning");
            return;
          }
          watcher = runtime.launch({
            command,
            label: command.split(/\s+/).slice(0, 2).join(" "),
            timeoutSeconds,
          });
        }
      } catch (error) {
        if (error instanceof MonitorLimitError) {
          notify(ctx, error.message, "warning");
        } else {
          notify(ctx, (error as Error).message, "error");
        }
        return;
      }
      notify(
        ctx,
        `watcher ${watcher.id} running (${watcher.mode}) — will ping when: ${watcher.watchingFor}`,
        "info",
      );
    },
  });

  pi.registerCommand("monitors", {
    description: "List active background watchers",
    handler: async (_args, ctx) => {
      const list = runtime.list();
      if (!list.length) {
        notify(ctx, "No active monitors.", "info");
        return;
      }
      for (const m of list) {
        notify(
          ctx,
          `${m.id}${m.label ? " · " + m.label : ""} [${m.mode}] ${m.alive ? "alive" : "dead"} · ${m.eventCount} events · last ${m.lastEventAt ?? "never"} · ${m.watchingFor}`,
          "info",
        );
      }
    },
  });

  pi.registerCommand("monitor-kill", {
    description: "Stop a background watcher by id (autocompletes live watcher ids)",
    getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
      const items = runtime
        .list()
        .filter((m) => m.id.startsWith(prefix))
        .map((m) => ({
          value: m.id,
          label: m.id,
          description: `${m.mode}${m.label ? " · " + m.label : ""}`,
        }));
      return items.length ? items : null;
    },
    handler: async (args, ctx) => {
      const id = args.trim();
      if (!id) {
        notify(ctx, "Usage: /monitor-kill <id>  (tab to autocomplete)", "warning");
        return;
      }
      const watcher = runtime.stop(id);
      if (!watcher) {
        notify(ctx, `No watcher ${id}.`, "warning");
        return;
      }
      notify(ctx, `Stopped watcher ${watcher.id}.`, "info");
    },
  });

  pi.registerCommand("monitor-kill-all", {
    description: "Stop ALL active background watchers",
    handler: async (_args, ctx) => {
      const stopped = runtime.stopAll();
      if (!stopped.length) {
        notify(ctx, "No active monitors.", "info");
        return;
      }
      for (const m of stopped) {
        notify(ctx, `Stopped watcher ${m.id}${m.label ? " · " + m.label : ""} (${m.mode}).`, "info");
      }
      // One consolidated custom message so the stop participates in model
      // context — without waking the model just because a human ran a
      // slash command.
      pi.sendMessage(
        {
          customType: MESSAGE_TYPE_STOP_ALL,
          content: buildStopAllSummary(stopped),
          display: true,
          details: { reason: "kill-all", watchers: stopped },
        },
        { triggerTurn: false, deliverAs: "steer" },
      );
    },
  });

  return runtime;
}
