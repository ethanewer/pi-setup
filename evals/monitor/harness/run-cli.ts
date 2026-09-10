/**
 * monitor-bench harness (live setup): runs one task headlessly through the
 * INSTALLED `pi` or `p` CLI in --mode rpc.
 *
 * The eval deliberately has no pinned copy of pi: the agent under test is
 * whatever the operator's setup currently provides (version, reasoning
 * patches, model catalog, compiled extension forks), so updating the setup
 * never requires touching the eval. The benchmark's controlled surface is
 * kept by pointing PI_CODING_AGENT_DIR at harness/pihome, whose only package
 * is the monitor fork — symlinked from the INSTALLED copy
 * (~/.pi/agent/local/pi-process-monitor-safe, which the setup's installer
 * compiles and keeps current), falling back to materializing this repo's
 * fork when no installed copy exists.
 *
 * RPC mode (not --mode json / -p) because one-shot pi exits at agent_settled
 * and drops active watchers: the bench's whole subject — watcher pings
 * waking an idle session — only exists in a live, held-open session. Events
 * are the same AgentSessionEvent stream the SDK emitted, so accounting.ts,
 * the transcript format, run.json, and score/score.py are unchanged.
 *
 * env:
 *   TASK      t1..t7
 *   RUN_DIR   results/<run-id> directory
 *   SEED      rng seed for fixture durations
 *   HARNESS   pi | p   (default pi; p runs the lean profile — no monitor,
 *             its wrapper owns PI_CODING_AGENT_DIR, so pihome is not used)
 *   MODEL     provider/model, default openrouter/z-ai/glm-5.3-flash
 *   BUDGET_S  optional override
 */
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync, appendFileSync, existsSync, symlinkSync, renameSync, lstatSync, readlinkSync, createWriteStream } from "node:fs";
import { createHash, randomBytes } from "node:crypto";
import net from "node:net";
import { spawn, spawnSync } from "node:child_process";
import { createTracker, textOf } from "./accounting.ts";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
// repo root (pi-setup): two levels above this eval's ROOT (see run-task history).
const EVALS_ROOT = path.resolve(ROOT, "..", "..");
const TASK = process.env.TASK ?? "t1";
const RUN_DIR = path.resolve(process.env.RUN_DIR ?? path.join(ROOT, "results", "dev"));
const SEED = process.env.SEED ?? "0";
const HARNESS = process.env.HARNESS ?? "pi";
const MODEL = process.env.MODEL ?? "openrouter/z-ai/glm-5.3-flash";
if (HARNESS !== "pi" && HARNESS !== "p") throw new Error(`HARNESS must be pi or p (got ${HARNESS})`);

const PIHOME = path.join(ROOT, "harness", "pihome");
const BUDGETS: Record<string, number> = { t1: 720, t2: 720, t3: 600, t4: 720, t5: 300, t6: 480, t7: 540 };
const BUDGET_S = Number(process.env.BUDGET_S ?? BUDGETS[TASK] ?? 600);
const QUIESCE_MS = 25_000;

// ---- monitor package: prefer the setup's INSTALLED compiled fork ----------
// The installed copy (~/.pi/agent/local/...) is produced by lib/install.mjs
// (copy fork + bun build index.ts -> index.js) and tracks setup updates, so
// symlinking it keeps this eval current with zero maintenance. A bare symlink
// to the repo fork is NOT sufficient: the manifest points at index.js, which
// the fork does not carry (build artifact), and pi then silently loads zero
// extensions. Hence the copy+compile fallback for setups without it.
if (HARNESS === "pi") {
  const pkgDest = path.join(PIHOME, "local", "pi-process-monitor-safe");
  const installed = path.join(process.env.HOME ?? "", ".pi", "agent", "local", "pi-process-monitor-safe");
  mkdirSync(path.dirname(pkgDest), { recursive: true });
  const installedOk = existsSync(path.join(installed, "extensions", "monitor", "index.js"));
  const compiledEntry = (p: string) => existsSync(path.join(p, "extensions", "monitor", "index.js"));
  // Create-once: seven tasks start concurrently and must never see this path
  // removed. A stale or broken entry is moved aside with an atomic rename
  // (never rmSync under a possible concurrent loader), and the fork-fallback
  // build lands via a temp dir + atomic rename.
  let pkgStat: ReturnType<typeof lstatSync> | null = null;
  try { pkgStat = lstatSync(pkgDest); } catch { pkgStat = null; }
  const pkgCurrent = pkgStat !== null && (
    (pkgStat.isSymbolicLink() && readlinkSync(pkgDest) === installed && installedOk) ||
    (!pkgStat.isSymbolicLink() && compiledEntry(pkgDest))
  );
  if (!pkgCurrent) {
    if (pkgStat !== null) {
      try { renameSync(pkgDest, `${pkgDest}.stale-${process.pid}`); } catch { /* another task won the race */ }
    }
    if (installedOk && !existsSync(pkgDest)) {
      try { symlinkSync(installed, pkgDest); } catch { /* loser of a create race; winner linked the same target */ }
    }
    if (!existsSync(pkgDest)) {
      const forkSrc = path.join(EVALS_ROOT, "forks", "pi-process-monitor-safe");
      if (!existsSync(path.join(forkSrc, "extensions", "monitor", "index.ts"))) {
        throw new Error(`no installed monitor fork at ${installed} and no repo fork at ${forkSrc}`);
      }
      const tmpDest = `${pkgDest}.build-${process.pid}`;
      rmSync(tmpDest, { recursive: true, force: true });
      cpSync(forkSrc, tmpDest, {
        recursive: true,
        filter: (src) => !src.split(path.sep).includes("node_modules"),
      });
      const tmpEntryJs = path.join(tmpDest, "extensions", "monitor", "index.js");
      const tmpJs = `${tmpEntryJs}.tmp-${process.pid}`;
      const r = spawnSync(
        "bun",
        ["build", path.join(tmpDest, "extensions", "monitor", "index.ts"),
         "--outfile", tmpJs, "--target", "bun", "--format", "esm", "--packages", "external"],
        { cwd: tmpDest },
      );
      if (r.status !== 0) throw new Error(`bun build failed for monitor extension: ${r.stderr?.toString().slice(0, 400)}`);
      renameSync(tmpJs, tmpEntryJs);
      try {
        renameSync(tmpDest, pkgDest);
      } catch {
        if (!compiledEntry(pkgDest)) throw new Error(`could not place the monitor package at ${pkgDest}`);
      }
    }
    // Best-effort cleanup of THIS process's move-aside/build leftovers only.
    for (const junk of [`${pkgDest}.stale-${process.pid}`, `${pkgDest}.build-${process.pid}`]) {
      try { rmSync(junk, { recursive: true, force: true }); } catch {}
    }
  }
  // Live model catalog: create-once symlink to the setup's refreshed store;
  // stale entries are renamed aside, never removed in place.
  const liveStore = path.join(process.env.HOME ?? "", ".pi", "agent", "models-store.json");
  const storeLink = path.join(PIHOME, "models-store.json");
  if (existsSync(liveStore)) {
    let storeStat: ReturnType<typeof lstatSync> | null = null;
    try { storeStat = lstatSync(storeLink); } catch { storeStat = null; }
    const storeOk = storeStat !== null && storeStat.isSymbolicLink() && readlinkSync(storeLink) === liveStore;
    if (!storeOk) {
      if (storeStat !== null) {
        const aside = `${storeLink}.stale-${process.pid}`;
        try { renameSync(storeLink, aside); rmSync(aside, { force: true }); } catch {}
      }
      if (!existsSync(storeLink)) {
        try { symlinkSync(liveStore, storeLink); } catch { /* race loser is fine */ }
      }
    }
  }
}

// ---- workspace (identical to the historical run-task.ts) ------------------
const taskDir = path.join(ROOT, "tasks", TASK);
const runDir = path.join(RUN_DIR, TASK);
const workDir = path.join(runDir, "work");
rmSync(runDir, { recursive: true, force: true });
mkdirSync(workDir, { recursive: true });
cpSync(path.join(taskDir, "fixture"), workDir, { recursive: true });

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
const NONCE = randomBytes(6).toString("hex");
const MB_PORT: number = await new Promise((resolve, reject) => {
  const srv = net.createServer();
  srv.unref();
  srv.on("error", reject);
  srv.listen(0, "127.0.0.1", () => {
    const port = (srv.address() as net.AddressInfo).port;
    srv.close(() => resolve(port));
  });
});

const eventsPath = path.join(runDir, "events.jsonl");
const transcriptPath = path.join(runDir, "transcript.jsonl");
const runLog = path.join(runDir, "harness.log");
const log = (msg: string) => appendFileSync(runLog, `${new Date().toISOString()} ${msg}\n`);
const transcript = (obj: any) => appendFileSync(transcriptPath, JSON.stringify(obj) + "\n");

// ---- watcher accounting (shared with accounting.selftest.ts) --------------
const tracker = createTracker();
const activeWatchers = tracker.activeWatchers;

const toolCounts: Record<string, number> = {};
let assistantTurns = 0;
let lastEventAt = Date.now();
let lastAssistantText = "";

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

// ---- launch the installed CLI in RPC mode ---------------------------------
const versionProbe = spawnSync(HARNESS, ["--version"], { encoding: "utf8", timeout: 60_000 });
const agentVersion = (versionProbe.stdout || "").trim().split("\n").pop() ?? "";

const childEnv: Record<string, string> = {
  ...(process.env as Record<string, string>),
  SEED,
  MB_NONCE: NONCE,
  MB_PORT: String(MB_PORT),
  PYTHONUNBUFFERED: "1",
};
if (HARNESS === "pi") {
  childEnv.PI_CODING_AGENT_DIR = PIHOME;
  delete childEnv.PI_CODING_AGENT_SESSION_DIR;
} // p's wrapper owns its profile dir; overriding it would not be p's setup.

const child = spawn(HARNESS, ["--mode", "rpc", "--no-session", "--model", MODEL], {
  cwd: workDir,
  env: childEnv,
  stdio: ["pipe", "pipe", "pipe"],
  detached: true, // own process group: budget kills must take the whole tree
});
const stderrPath = path.join(runDir, "cli-stderr.log");
const stderrStream = createWriteStream(stderrPath);
child.stderr?.pipe(stderrStream);

let promptError: string | undefined;
let settledSeen = false;
let retriedEmpty = false;
let childExited: { code: number | null } | null = null;
child.on("exit", (code) => { childExited = { code }; });

function send(obj: any) {
  try { child.stdin?.write(JSON.stringify(obj) + "\n"); } catch (e: any) { log(`stdin write error: ${e?.message}`); }
}

let buf = "";
function consumeLine(lineRaw: string) {
  const line = lineRaw.replace(/\r$/, "");
  if (!line.trim()) return;
  let event: any;
  try { event = JSON.parse(line); } catch { return; }
  lastEventAt = Date.now();
  if (event.type === "response") {
    if (event.command === "prompt" && event.success === false) {
      promptError = String(event.error ?? "prompt rejected");
      log(`prompt error: ${promptError}`);
    }
    appendFileSync(eventsPath, JSON.stringify({ ts: Date.now(), type: "rpc_response", command: event.command, success: event.success }) + "\n");
    return;
  }
  handleEvent(event);
  if (event.type === "agent_settled") {
    const first = !settledSeen;
    settledSeen = true;
    if (first && !retriedEmpty && Object.keys(toolCounts).length === 0 && lastAssistantText.trim() === "") {
      retriedEmpty = true;
      log("empty first turn; retrying prompt once");
      setTimeout(() => send({ id: "p2", type: "prompt", message: prompt }), 2000);
    }
  }
  const slim: any = { ts: Date.now(), type: event.type };
  if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
    slim.kind = "text_delta";
    slim.len = event.assistantMessageEvent.delta?.length ?? 0;
  }
  appendFileSync(eventsPath, JSON.stringify(slim) + "\n");
}
child.stdout?.setEncoding("utf8");
child.stdout?.on("data", (chunk: string) => {
  buf += chunk;
  let idx: number;
  while ((idx = buf.indexOf("\n")) >= 0) {
    consumeLine(buf.slice(0, idx));
    buf = buf.slice(idx + 1);
  }
});
child.stdout?.on("end", () => { if (buf.trim()) consumeLine(buf); buf = ""; });

const startedAt = new Date().toISOString();
const t0 = Date.now();
log(`task=${TASK} harness=${HARNESS} agentVersion=${agentVersion} model=${MODEL} seed=${SEED} budget=${BUDGET_S}s workdir=${workDir}`);
send({ id: "p1", type: "prompt", message: prompt });

// ---- quiescence / budget loop ---------------------------------------------
let exitReason = "budget";
while (Date.now() - t0 < BUDGET_S * 1000) {
  await new Promise((r) => setTimeout(r, 2000));
  if (childExited) break; // CLI died on its own; recorded below
  const idleMs = Date.now() - lastEventAt;
  const active = activeWatchers();
  if (settledSeen && active === 0 && idleMs >= QUIESCE_MS) { exitReason = "settled"; break; }
}
if (exitReason === "budget") log(`budget reached; activeWatchers=${activeWatchers()}`);
else if (childExited) log(`cli exited early code=${childExited.code}`);
else log(`settled after ${Math.round((Date.now() - t0) / 1000)}s`);

// An early CLI exit before the budget is its own outcome, not a budget hit.
if (childExited && exitReason === "budget" && Date.now() - t0 < BUDGET_S * 1000 - 3000) {
  exitReason = childExited.code === 0 ? "cli_exited_0" : `cli_rc_${childExited.code}`;
}

// ---- shutdown: abort, close stdin, kill the process group ------------------
function killGroup(sig: NodeJS.Signals) {
  try { process.kill(-child.pid!, sig); } catch { try { child.kill(sig); } catch {} }
}
if (!childExited) {
  send({ type: "abort" });
  try { child.stdin?.end(); } catch {}
  killGroup("SIGTERM");
  await new Promise<void>((resolve) => {
    const t = setTimeout(() => { killGroup("SIGKILL"); resolve(); }, 5000);
    child.on("exit", () => { clearTimeout(t); resolve(); });
  });
}
if (exitReason !== "settled" && exitReason !== "budget" && !String(exitReason).startsWith("cli_")) {
  exitReason = `cli_rc_${childExited?.code}`;
}

const finalText = lastAssistantText;

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
  harness: HARNESS,
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
  agentVersion,
  piVersion: agentVersion, // compat with meta readers from the pinned-SDK era
};
writeFileSync(path.join(runDir, "run.json"), JSON.stringify(run, null, 2));
log(`done: ${JSON.stringify({ exitReason, durationMs: run.durationMs, watcherStarts: run.watcherStarts, toolCounts })}`);
console.log(`[${HARNESS}:${TASK}] finished (${exitReason}) in ${Math.round(run.durationMs / 1000)}s`);
process.exit(0);
