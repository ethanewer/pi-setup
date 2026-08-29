/**
 * browser-bench harness: runs one task headlessly through the pi SDK.
 *
 * env:
 *   TASK      t1..t5
 *   ARM       agent-browser | agent-browser-guided | playwright | devtools
 *   RUN_DIR   results/<run-id> directory
 *   SEED      rng seed for the site's catalog and ground truth
 *   MODEL     provider/model, default openrouter/z-ai/glm-5.3-flash
 *
 * The harness owns the fixture site process (per-run ephemeral port, per-run
 * nonce), the per-run browser profile (MCP arms), and the .mcp.json bridge
 * config (MCP arms). The model's workspace starts empty except that config.
 */
import { cpSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, existsSync, rmSync, symlinkSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import net from "node:net";
import { spawn, type ChildProcess } from "node:child_process";
import path from "node:path";
import { createAgentSession, DefaultResourceLoader, SessionManager } from "@earendil-works/pi-coding-agent";
import { getModel } from "@earendil-works/pi-ai/compat";

const ROOT = path.resolve(import.meta.dirname, "..");
const EVALS_ROOT = path.resolve(ROOT, "..", "..");
const TASK = process.env.TASK ?? "t1";
const ARM = process.env.ARM ?? "agent-browser";
const RUN_DIR = path.resolve(process.env.RUN_DIR ?? path.join(ROOT, "results", "dev"));
const SEED = process.env.SEED ?? "0";
const MODEL = process.env.MODEL ?? "openrouter/z-ai/glm-5.3-flash";
const BUDGETS: Record<string, number> = { t1: 600, t2: 480, t3: 600, t4: 480, t5: 300 };
const BUDGET_S = Number(process.env.BUDGET_S ?? BUDGETS[TASK] ?? 600);
const QUIESCE_MS = 30_000;

const ARMS = ["agent-browser", "agent-browser-guided", "playwright", "devtools"] as const;
if (!ARMS.includes(ARM as any)) throw new Error(`unknown ARM '${ARM}' (want one of ${ARMS.join(", ")})`);

const PIHOME = path.join(ROOT, "harness", "pihome");
const vendorAdapter = path.join(ROOT, "vendor", "node_modules", "pi-mcp-adapter");
if (!existsSync(vendorAdapter)) throw new Error("pi-mcp-adapter missing from vendor/ — run: (cd vendor && bun add pi-mcp-adapter@2.31.0)");

// ---- per-run directories ----
const runDir = path.join(RUN_DIR, TASK);
const workDir = path.join(runDir, "work");
const profileDir = path.join(runDir, "browser-profile");
rmSync(runDir, { recursive: true, force: true });
mkdirSync(workDir, { recursive: true });
mkdirSync(path.join(PIHOME, "local"), { recursive: true });

// ---- agent dir: exactly one browser tool surface per arm ----
function linkPackage(src: string, name: string) {
  if (!existsSync(src)) throw new Error(`package source missing: ${src}`);
  const dst = path.join(PIHOME, "local", name);
  try { rmSync(dst); } catch { /* not a symlink */ }
  symlinkSync(src, dst);
  return `local/${name}`;
}
const settingsPath = path.join(PIHOME, "settings.json");
let packages: string[] = [];
if (ARM === "agent-browser" || ARM === "agent-browser-guided") {
  const candidates = [
    path.join(EVALS_ROOT, "forks", "pi-agent-browser-native-safe"),
    path.join(process.env.HOME ?? "", ".pi", "agent", "local", "pi-agent-browser-native-safe"),
  ];
  const src = candidates.find((p) => existsSync(p));
  if (!src) throw new Error(`pi-agent-browser-native-safe not found in: ${candidates.join(", ")}`);
  packages = [linkPackage(src, "pi-agent-browser-native")];
} else {
  packages = [linkPackage(vendorAdapter, "pi-mcp-adapter")];
}
writeFileSync(settingsPath, JSON.stringify({
  defaultThinkingLevel: "medium",
  packages,
}, null, 2) + "\n");

// ---- per-run site ----
const NONCE = randomBytes(6).toString("hex");
const PORT: number = await new Promise((resolve, reject) => {
  const srv = net.createServer();
  srv.unref();
  srv.on("error", reject);
  srv.listen(0, "127.0.0.1", () => {
    const port = (srv.address() as net.AddressInfo).port;
    srv.close(() => resolve(port));
  });
});
// Site source, request log, and ground truth live in a random temp dir far from
// the model's workspace: the model reads ../ and greps the repo, and both the
// ground truth and the challenge mechanics must not be discoverable there.
const siteDir = path.join(tmpdir(), `browser-bench-${NONCE}`);
mkdirSync(siteDir, { recursive: true });
const siteSrc = path.join(siteDir, "server.ts");
cpSync(path.join(ROOT, "harness", "site", "server.ts"), siteSrc);
const siteLog = path.join(siteDir, "sitelog.jsonl");
const siteTruth = path.join(siteDir, "ground_truth.json");
const site = spawn(process.execPath, [siteSrc], {
  env: {
    ...process.env,
    SITE_PORT: String(PORT),
    SEED,
    SITE_NONCE: NONCE,
    SITE_LOG: siteLog,
    SITE_TRUTH: siteTruth,
  },
  stdio: ["ignore", "pipe", "pipe"],
});
let siteOut = "";
site.stdout.on("data", (d: Buffer) => { siteOut += d.toString(); });
site.stderr.on("data", (d: Buffer) => { siteOut += d.toString(); });
const baseUrl = await new Promise<string>((resolve, reject) => {
  const t0 = Date.now();
  const iv = setInterval(async () => {
    const m = siteOut.match(/SITE_PORT=(\d+)/);
    if (m) { clearInterval(iv); resolve(`http://127.0.0.1:${m[1]}`); }
    else if (Date.now() - t0 > 15_000) { clearInterval(iv); reject(new Error(`site did not start: ${siteOut}`)); }
  }, 100);
});

// ---- MCP bridge config (MCP arms only) ----
if (ARM === "playwright" || ARM === "devtools") {
  const serverArgs = ARM === "playwright"
    ? ["-y", "@playwright/mcp@0.0.79", "--headless", "--no-sandbox", "--user-data-dir", profileDir]
    : ["-y", "chrome-devtools-mcp@1.8.0", "--headless", "--no-usage-statistics", "--no-update-checks",
       "--user-data-dir", profileDir];
  const server = ARM === "playwright"
    ? { command: "npx", args: serverArgs }
    : { command: "npx", args: serverArgs };
  writeFileSync(path.join(workDir, ".mcp.json"), JSON.stringify({
    mcpServers: { [ARM === "playwright" ? "playwright" : "chrome-devtools"]: { ...server, trace: true } },
  }, null, 2) + "\n");
}

// ---- prompt ----
let prompt = readFileSync(path.join(ROOT, "tasks", TASK, "prompt.txt"), "utf8");
// Runtime-bound credentials: the seeded password only exists in the site's
// ground-truth file, so the prompt cannot be answered without the live site.
const truthNow = JSON.parse(readFileSync(siteTruth, "utf8"));
prompt = prompt.replaceAll("{{PASSWORD}}", truthNow.login.password);
if (ARM === "agent-browser-guided") {
  // Documented deviation for the +guidance arm: context the user could provide.
  prompt += "\n\nA few tips that may help: if a site shows a bot check or CAPTCHA, read what it asks for and complete it (type the code it shows, or tick the checkbox) instead of giving up or retrying blindly. If a page says it is checking your browser, wait for it to finish rather than refreshing. If you hit HTTP 429, wait the stated number of seconds before retrying. Prefer real page navigation over fetching URLs with curl when a site checks for bots.\n";
}
prompt += `\n\nThe site is running at ${baseUrl} .\n`;

const eventsPath = path.join(runDir, "events.jsonl");
const transcriptPath = path.join(runDir, "transcript.jsonl");
const runLog = path.join(runDir, "harness.log");
const log = (msg: string) => appendFileSync(runLog, `${new Date().toISOString()} ${msg}\n`);
const transcript = (obj: any) => appendFileSync(transcriptPath, JSON.stringify(obj) + "\n");

const textOf = (c: any): string =>
  Array.isArray(c) ? c.map((b) => (typeof b === "string" ? b : b?.text ?? "")).join("") : String(c ?? "");

const toolCounts: Record<string, number> = {};
const toolCalls: { tool: string; args: any }[] = [];
let assistantTurns = 0;
let lastEventAt = Date.now();
let lastAssistantText = "";
let usageIn = 0, usageOut = 0, usageCacheRead = 0;

function handleEvent(event: any) {
  switch (event.type) {
    case "tool_execution_start": {
      toolCounts[event.toolName] = (toolCounts[event.toolName] ?? 0) + 1;
      toolCalls.push({ tool: event.toolName, args: event.args });
      transcript({ ts: Date.now(), type: "tool_start", toolName: event.toolName, toolCallId: event.toolCallId, args: event.args });
      break;
    }
    case "tool_execution_end": {
      transcript({ ts: Date.now(), type: "tool_end", toolName: event.toolName, toolCallId: event.toolCallId, isError: event.isError, text: textOf(event.result?.content ?? event.result).slice(0, 8000) });
      break;
    }
    case "message_start": {
      const m = event.message;
      if (m && m.role !== "assistant" && m.role !== "toolResult") {
        transcript({ ts: Date.now(), type: "user_message", role: m.role, customType: m.customType, text: textOf(m.content).slice(0, 4000) });
      }
      break;
    }
    case "turn_end": {
      assistantTurns++;
      const m = event.message;
      const u = (m as any)?.usage;
      if (u) { usageIn += u.input ?? 0; usageOut += u.output ?? 0; usageCacheRead += u.cacheRead ?? 0; }
      const text = textOf(m?.content).trim();
      if (text) lastAssistantText = text;
      transcript({ ts: Date.now(), type: "turn_end", text: text.slice(0, 8000), toolResults: (event.toolResults ?? []).map((t: any) => ({ toolName: t.toolName, isError: t.isError, text: textOf(t.content).slice(0, 2000) })) });
      break;
    }
  }
}

// ---- model + session ----
const [provider, ...rest] = MODEL.split("/");
const model = getModel(provider as any, rest.join("/"));
if (!model) throw new Error(`model not found: ${MODEL}`);

const resourceLoader = new DefaultResourceLoader({ cwd: workDir, agentDir: PIHOME });
await resourceLoader.reload();
process.chdir(workDir);

const { session } = await createAgentSession({
  cwd: workDir,
  agentDir: PIHOME,
  model,
  thinkingLevel: "medium",
  resourceLoader,
  sessionManager: SessionManager.inMemory(workDir),
});
// Deliver session_start to extensions — required for lazy MCP gateways
// (print-mode does this on every run; the bare SDK does not).
await (session as any).bindExtensions({
  mode: "print",
  commandContextActions: { waitForIdle: () => session.waitForIdle() },
});

session.subscribe((event: any) => {
  lastEventAt = Date.now();
  handleEvent(event);
  const slim: any = { ts: Date.now(), type: event.type };
  if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
    slim.kind = "text_delta";
    slim.len = event.assistantMessageEvent.delta?.length ?? 0;
  }
  appendFileSync(eventsPath, JSON.stringify(slim) + "\n");
});

const startedAt = new Date().toISOString();
const t0 = Date.now();
log(`task=${TASK} arm=${ARM} model=${MODEL} seed=${SEED} budget=${BUDGET_S}s site=${baseUrl} workdir=${workDir}`);

let promptError: string | undefined;
const promptPromise = (async () => {
  try {
    await session.prompt(prompt);
    log("initial prompt turn finished");
    if (Object.keys(toolCounts).length === 0 && lastAssistantText.trim() === "") {
      log("empty first turn; retrying prompt once");
      await new Promise((r) => setTimeout(r, 2000));
      await session.prompt(prompt);
      log("retry turn finished");
    }
  } catch (err: any) {
    promptError = String(err?.message ?? err);
    log(`prompt error: ${promptError}`);
  }
})();

// ---- quiescence / budget loop ----
let exitReason = "budget";
while (Date.now() - t0 < BUDGET_S * 1000) {
  await new Promise((r) => setTimeout(r, 2000));
  const idleMs = Date.now() - lastEventAt;
  if (idleMs >= QUIESCE_MS) { exitReason = "settled"; break; }
}
if (exitReason === "budget") {
  // Aborting unwedges an in-flight prompt so the harness can still record the run.
  log("budget reached; aborting session");
  try { await session.abort(); } catch (err: any) { log(`abort error: ${err?.message}`); }
  await Promise.race([promptPromise, new Promise((r) => setTimeout(r, 55_000))]);
}

const finalText = lastAssistantText;
try { session.dispose(); } catch (err: any) { log(`dispose error: ${err?.message}`); }

// ---- stop the site (SIGTERM → summary line in the log), collect evidence, scrub ----
let siteSummary: Record<string, number> | undefined;
await new Promise<void>((resolve) => {
  site.on("exit", () => resolve());
  site.kill("SIGTERM");
  setTimeout(() => { try { site.kill("SIGKILL"); } catch {} resolve(); }, 5000);
});
try {
  siteSummary = JSON.parse(readFileSync(siteLog, "utf8").trim().split("\n").reverse().find((l) => l.includes("site_summary"))!).stats;
} catch { /* scorer handles absence */ }
// Evidence out of the temp dir before it disappears.
try { cpSync(siteLog, path.join(runDir, "sitelog.jsonl")); } catch {}
try { cpSync(siteTruth, path.join(runDir, "ground_truth.json")); } catch {}
try { rmSync(siteDir, { recursive: true, force: true }); } catch {}

// ---- MCP browser cleanup: kill this run's profile-bound servers ----
const killed = await new Promise<number>((resolve) => {
  const p = spawn("pkill", ["-f", profileDir]);
  p.on("exit", (code) => resolve(code === 0 ? 1 : 0));
  setTimeout(() => resolve(0), 5000);
});

const endedAt = new Date().toISOString();
const run = {
  task: TASK, arm: ARM, model: MODEL, seed: SEED, nonce: NONCE,
  baseUrl, budgetSeconds: BUDGET_S, startedAt, endedAt,
  durationMs: Date.now() - t0, exitReason, promptError,
  assistantTurns, toolCounts, toolCalls, packages,
  usage: { input: usageIn, output: usageOut, cacheRead: usageCacheRead },
  siteSummary, finalText: finalText.slice(0, 6000),
  mcpCleanupKills: killed,
};
writeFileSync(path.join(runDir, "run.json"), JSON.stringify(run, null, 2));
log(`done: ${JSON.stringify({ exitReason, durationMs: run.durationMs, toolCounts })}`);
console.log(`[${ARM}/${TASK}] finished (${exitReason}) in ${Math.round(run.durationMs / 1000)}s`);
process.exit(0);
