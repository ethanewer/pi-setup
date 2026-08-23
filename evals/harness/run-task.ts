/**
 * monitor-bench harness: runs one task headlessly through the pi SDK.
 *
 * env:
 *   TASK      t1..t7
 *   RUN_DIR   results/<run-id> directory
 *   SEED      rng seed for fixture durations
 *   MODEL     provider/model, default openrouter/deepseek/deepseek-v4-flash-0731
 */
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync, appendFileSync, existsSync, symlinkSync } from "node:fs";
import { createHash, randomBytes } from "node:crypto";
import net from "node:net";
import { createTracker, textOf } from "./accounting.ts";
import path from "node:path";
import { createAgentSession, DefaultResourceLoader, SessionManager } from "@earendil-works/pi-coding-agent";
import { getModel } from "@earendil-works/pi-ai/compat";

const ROOT = path.resolve(import.meta.dirname, "..");
const EVALS_ROOT = path.resolve(ROOT, "..");
const TASK = process.env.TASK ?? "t1";
const RUN_DIR = path.resolve(process.env.RUN_DIR ?? path.join(ROOT, "results", "dev"));
const SEED = process.env.SEED ?? "0";
const MODEL = process.env.MODEL ?? "openrouter/deepseek/deepseek-v4-flash-0731";
const PIHOME = path.join(ROOT, "harness", "pihome");

// Link the monitor extension package into the isolated agent dir.
// Prefer this repo's vendored fork; fall back to the user's installed copy.
const pkgLink = path.join(PIHOME, "local", "pi-process-monitor-safe");
const candidates = [
  path.join(EVALS_ROOT, "forks", "pi-process-monitor-safe"),
  path.join(process.env.HOME ?? "", ".pi", "agent", "local", "pi-process-monitor-safe"),
];
const pkgSrc = candidates.find((p) => existsSync(path.join(p, "extensions", "monitor", "index.ts")));
if (!pkgSrc) throw new Error(`pi-process-monitor-safe not found in: ${candidates.join(", ")}`);
mkdirSync(path.dirname(pkgLink), { recursive: true });
try { rmSync(pkgLink); } catch {}
try {
  symlinkSync(pkgSrc, pkgLink);
} catch {
  if (!existsSync(pkgLink)) throw new Error(`failed to link ${pkgSrc} -> ${pkgLink}`);
}
const BUDGETS: Record<string, number> = { t1: 720, t2: 720, t3: 600, t4: 720, t5: 300, t6: 480, t7: 540 };
const BUDGET_S = Number(process.env.BUDGET_S ?? BUDGETS[TASK] ?? 600);
const QUIESCE_MS = 25_000;

const taskDir = path.join(ROOT, "tasks", TASK);
const runDir = path.join(RUN_DIR, TASK);
const workDir = path.join(runDir, "work");
rmSync(runDir, { recursive: true, force: true });
mkdirSync(workDir, { recursive: true });
cpSync(path.join(taskDir, "fixture"), workDir, { recursive: true });

// Fixture integrity baseline: sha256 of every shipped fixture file.
function hashTree(dir: string, base: string, out: Record<string, string>) {
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name);
    const rel = path.relative(base, p);
    if (statSync(p).isDirectory()) hashTree(p, base, out);
    else out[rel] = createHash("sha256").update(readFileSync(p)).digest("hex");
  }
}
const fixtureHashes: Record<string, string> = {};
hashTree(workDir, workDir, fixtureHashes);

const prompt = readFileSync(path.join(taskDir, "prompt.txt"), "utf8");
// Match pi's TUI: the agent process cwd is the session cwd, so relative paths in
// monitor/poll commands resolve where the model expects.
process.chdir(workDir);
process.env.SEED = SEED;
process.env.PYTHONUNBUFFERED = "1";
// Per-run values baked into job artifacts so ground truth depends on actually running.
const NONCE = randomBytes(6).toString("hex");
// Grab a real free port (hash-based picks collide across large parallel batches).
const MB_PORT: number = await new Promise((resolve, reject) => {
  const srv = net.createServer();
  srv.unref();
  srv.on("error", reject);
  srv.listen(0, "127.0.0.1", () => {
    const port = (srv.address() as net.AddressInfo).port;
    srv.close(() => resolve(port));
  });
});
process.env.MB_NONCE = NONCE;
process.env.MB_PORT = String(MB_PORT);

const eventsPath = path.join(runDir, "events.jsonl");
const transcriptPath = path.join(runDir, "transcript.jsonl");
const runLog = path.join(runDir, "harness.log");
const log = (msg: string) => {
  const line = `${new Date().toISOString()} ${msg}`;
  appendFileSync(runLog, line + "\n");
};

// ---- watcher accounting (shared with accounting.selftest.ts) ----
const tracker = createTracker();
const activeWatchers = tracker.activeWatchers;

const toolCounts: Record<string, number> = {};
let assistantTurns = 0;
let lastEventAt = Date.now();
let lastAssistantText = "";
const transcript = (obj: any) => appendFileSync(transcriptPath, JSON.stringify(obj) + "\n");

function handleEvent(event: any) {
  tracker.handle(event);
  switch (event.type) {
    case "tool_execution_start": {
      toolCounts[event.toolName] = (toolCounts[event.toolName] ?? 0) + 1;
      transcript({ ts: Date.now(), type: "tool_start", toolName: event.toolName, toolCallId: event.toolCallId, args: event.args });
      break;
    }
    case "tool_execution_end": {
      const text = textOf(event.result?.content ?? event.result);
      transcript({ ts: Date.now(), type: "tool_end", toolName: event.toolName, toolCallId: event.toolCallId, isError: event.isError, text: text.slice(0, 8000) });
      break;
    }
    case "message_start": {
      const m = event.message;
      if (m && m.role !== "assistant" && m.role !== "toolResult") {
        const text = textOf(m.content);
        transcript({ ts: Date.now(), type: "user_message", role: m.role, customType: m.customType, text: text.slice(0, 4000) });
      }
      break;
    }
    case "queue_update": {
      const steering = event.steering ?? [];
      if (steering.length) transcript({ ts: Date.now(), type: "steering", texts: steering.map((s: string) => s.slice(0, 2000)) });
      break;
    }
    case "turn_end": {
      assistantTurns++;
      const m = event.message;
      const text = textOf(m?.content).trim();
      if (text) lastAssistantText = text;
      transcript({ ts: Date.now(), type: "turn_end", text: text.slice(0, 8000), toolResults: (event.toolResults ?? []).map((t: any) => ({ toolName: t.toolName, isError: t.isError, text: textOf(t.content).slice(0, 2000) })) });
      break;
    }
  }
}

// ---- session setup ----
const [provider, ...rest] = MODEL.split("/");
const modelId = rest.join("/");
const model = getModel(provider as any, modelId);
if (!model) throw new Error(`model not found: ${MODEL}`);

const resourceLoader = new DefaultResourceLoader({ cwd: workDir, agentDir: PIHOME });
await resourceLoader.reload();

const { session } = await createAgentSession({
  cwd: workDir,
  agentDir: PIHOME,
  model,
  thinkingLevel: "medium",
  resourceLoader,
  sessionManager: SessionManager.inMemory(workDir),
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
log(`task=${TASK} model=${MODEL} seed=${SEED} budget=${BUDGET_S}s workdir=${workDir}`);

let promptError: string | undefined;
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

// ---- quiescence loop ----
let exitReason = "budget";
while (Date.now() - t0 < BUDGET_S * 1000) {
  await new Promise((r) => setTimeout(r, 2000));
  const idleMs = Date.now() - lastEventAt;
  const active = activeWatchers();
  if (active === 0 && idleMs >= QUIESCE_MS) {
    exitReason = "settled";
    break;
  }
}
if (exitReason === "budget") log(`budget reached; activeWatchers=${activeWatchers()}`);
else log(`settled after ${Math.round((Date.now() - t0) / 1000)}s`);

const finalText = lastAssistantText;

// ---- cleanup: dispose session, kill leftover fixture processes ----
try {
  session.dispose();
} catch (err: any) {
  log(`dispose error: ${err?.message}`);
}
function killPidFiles(dir: string) {
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name);
    try {
      if (statSync(p).isDirectory()) killPidFiles(p);
      else if (name.endsWith(".pid")) {
        const pid = Number(readFileSync(p, "utf8").trim());
        if (pid > 0) {
          try { process.kill(pid, "SIGTERM"); log(`killed leftover pid ${pid} (${p})`); } catch {}
        }
      }
    } catch {}
  }
}
killPidFiles(workDir);

const endedAt = new Date().toISOString();
const run = {
  task: TASK,
  model: MODEL,
  seed: SEED,
  nonce: NONCE,
  mbPort: MB_PORT,
  budgetSeconds: BUDGET_S,
  startedAt,
  endedAt,
  durationMs: Date.now() - t0,
  exitReason,
  promptError,
  ...tracker.stats(),
  assistantTurns,
  toolCounts,
  fixtureHashes,
  finalText: finalText.slice(0, 4000),
};
writeFileSync(path.join(runDir, "run.json"), JSON.stringify(run, null, 2));
log(`done: ${JSON.stringify({ exitReason, durationMs: run.durationMs, watcherStarts: run.watcherStarts, toolCounts })}`);
console.log(`[${TASK}] finished (${exitReason}) in ${Math.round(run.durationMs / 1000)}s`);
process.exit(0);
