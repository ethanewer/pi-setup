/**
 * browser-bench harness: runs one task headlessly through one of the setup's
 * live harnesses — pi or p (installed CLIs, --mode rpc), occ (Claude Code via
 * the occ wrapper), or ocdx (Codex CLI via the ocdx wrapper).
 *
 * env:
 *   TASK      t1..t5
 *   ARM       agent-browser | agent-browser-guided | playwright | devtools
 *             | cli-agent-browser | cli-playwright   (pi harness only; other
 *             harnesses run their native surface and record "<h>-native")
 *   RUN_DIR   results/<run-id> directory
 *   SEED      rng seed for the site's catalog and ground truth
 *   MODEL     provider/model for pi/p (default openrouter/z-ai/glm-5.3-flash);
 *             occ/ocdx receive the bare OpenRouter slug (prefix stripped)
 *   HARNESS   pi | p | occ | ocdx   (default pi)
 *
 * The eval has NO pinned pi copy: pi/p resolve to the installed CLIs (version,
 * patches, and catalog come from the live setup), and occ/ocdx resolve to the
 * installed wrappers. The harness owns the fixture site process (per-run
 * ephemeral port, per-run nonce), the per-run browser profile (MCP arms), and
 * the .mcp.json bridge config (MCP arms, pi harness). The model's workspace
 * starts empty except that config.
 *
 * RPC mode for pi/p because one-shot print modes exit at agent_settled and
 * drop in-flight work; the RPC event stream is the same AgentSessionEvent
 * stream the SDK emitted, so transcript/run.json/score.py are unchanged.
 */
import { cpSync, mkdirSync, readFileSync, readdirSync, writeFileSync, appendFileSync, existsSync, rmSync, symlinkSync, lstatSync, readlinkSync, renameSync, createWriteStream } from "node:fs";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import net from "node:net";
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
const EVALS_ROOT = path.resolve(ROOT, "..", "..");
const TASK = process.env.TASK ?? "t1";
const ARM = process.env.ARM ?? "agent-browser";
const RUN_DIR = path.resolve(process.env.RUN_DIR ?? path.join(ROOT, "results", "dev"));
const SEED = process.env.SEED ?? "0";
const MODEL = process.env.MODEL ?? "openrouter/z-ai/glm-5.3-flash";
const HARNESS = process.env.HARNESS ?? "pi";
const BUDGETS: Record<string, number> = { t1: 600, t2: 480, t3: 600, t4: 480, t5: 300 };
const BUDGET_S = Number(process.env.BUDGET_S ?? BUDGETS[TASK] ?? 600);
const QUIESCE_MS = 30_000;

if (!["pi", "p", "occ", "ocdx"].includes(HARNESS)) throw new Error(`unknown HARNESS '${HARNESS}'`);
const ARMS = [
  "agent-browser", "agent-browser-guided", "playwright", "devtools",
  "cli-agent-browser", "cli-playwright",
] as const;
const isPi = HARNESS === "pi" || HARNESS === "p";
const effectiveArm = HARNESS === "pi" ? ARM : `${HARNESS}-native`;
if (HARNESS === "pi" && !ARMS.includes(ARM as any)) throw new Error(`unknown ARM '${ARM}' (want one of ${ARMS.join(", ")})`);

const PIHOME = path.join(ROOT, "harness", `pihome-${ARM}`);
const vendorAdapter = path.join(ROOT, "vendor", "node_modules", "pi-mcp-adapter");
if (HARNESS === "pi" && (ARM === "playwright" || ARM === "devtools") && !existsSync(vendorAdapter)) {
  throw new Error("pi-mcp-adapter missing from vendor/ — run: (cd vendor && bun add pi-mcp-adapter@2.31.0)");
}

// ---- per-run directories ----
const runDir = path.join(RUN_DIR, TASK);
const workDir = path.join(runDir, "work");
const profileDir = path.join(runDir, "browser-profile");
rmSync(runDir, { recursive: true, force: true });
mkdirSync(workDir, { recursive: true });

// ---- agent dir: exactly one browser tool surface per arm (pi harness) -----
// Parallel tasks of one arm share the PIHOME: create-once, never rm (races).
function linkPackage(src: string, name: string) {
  if (!existsSync(src)) throw new Error(`package source missing: ${src}`);
  const dst = path.join(PIHOME, "local", name);
  if (!existsSync(dst)) {
    mkdirSync(path.dirname(dst), { recursive: true });
    try { symlinkSync(src, dst); } catch { /* lost race; the winner linked the same src */ }
  }
  return `local/${name}`;
}
let packages: string[] = [];
if (HARNESS === "pi") {
  mkdirSync(path.join(PIHOME, "local"), { recursive: true });
  const settingsPath = path.join(PIHOME, "settings.json");
  if (ARM === "agent-browser" || ARM === "agent-browser-guided") {
    // The agent-browser fork is an eval-side vendored component (not part of
    // the installed setup): prefer an installed copy, then this repo's fork,
    // then sibling pi-setup* checkouts (the browser-eval work may live on its
    // own branch checkout, like convert-pi-traces' checkout scan).
    const candidates = [
      path.join(process.env.HOME ?? "", ".pi", "agent", "local", "pi-agent-browser-native-safe"),
      path.join(EVALS_ROOT, "forks", "pi-agent-browser-native-safe"),
    ];
    try {
      const home = process.env.HOME ?? "";
      for (const dir of readdirSync(home).sort()) {
        if (dir.startsWith("pi-setup") && dir !== "pi-setup") {
          candidates.push(path.join(home, dir, "forks", "pi-agent-browser-native-safe"));
        }
      }
    } catch { /* no sibling scan */ }
    const src = candidates.find((p) => existsSync(path.join(p, "package.json")));
    if (!src) throw new Error(`pi-agent-browser-native-safe not found in: ${candidates.join(", ")}`);
    packages = [linkPackage(src, "pi-agent-browser-native")];
  } else if (ARM === "playwright" || ARM === "devtools") {
    packages = [linkPackage(vendorAdapter, "pi-mcp-adapter")];
  }
  // else: CLI arms load NO packages — the browser is a CLI on PATH, taught by a skill.
  writeFileSync(settingsPath, JSON.stringify({ defaultThinkingLevel: "medium", packages }, null, 2) + "\n");

  // CLI arms: install the how-to skill into the agent dir (create-once).
  if (ARM === "cli-agent-browser" || ARM === "cli-playwright") {
    const skillName = ARM === "cli-agent-browser" ? "agent-browser-cli" : "playwright-cli";
    const skillDst = path.join(PIHOME, "skills", skillName);
    if (!existsSync(path.join(skillDst, "SKILL.md"))) {
      mkdirSync(skillDst, { recursive: true });
      cpSync(path.join(ROOT, "harness", "skills", skillName, "SKILL.md"), path.join(skillDst, "SKILL.md"));
    }
  }

  // Live model catalog from the setup (shared pihome: create-once).
  const liveStore = path.join(process.env.HOME ?? "", ".pi", "agent", "models-store.json");
  const storeLink = path.join(PIHOME, "models-store.json");
  if (existsSync(liveStore)) {
    let linked = false;
    try { linked = lstatSync(storeLink).isSymbolicLink() && readlinkSync(storeLink) === liveStore; } catch { linked = false; }
    if (!linked) {
      // Rename-aside, never rmSync in place: five tasks share this PIHOME and
      // a concurrent pi startup must not see the catalog vanish mid-read.
      if (existsSync(storeLink)) {
        const aside = `${storeLink}.stale-${process.pid}`;
        try { renameSync(storeLink, aside); rmSync(aside, { force: true }); } catch {}
      }
      if (!existsSync(storeLink)) {
        try { symlinkSync(liveStore, storeLink); } catch { /* race loser is fine */ }
      }
    }
  }
}

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
  const iv = setInterval(() => {
    const m = siteOut.match(/SITE_PORT=(\d+)/);
    if (m) { clearInterval(iv); resolve(`http://127.0.0.1:${m[1]}`); }
    else if (Date.now() - t0 > 15_000) { clearInterval(iv); reject(new Error(`site did not start: ${siteOut}`)); }
  }, 100);
});

// ---- MCP bridge config (pi harness, MCP arms only) ----
if (HARNESS === "pi" && (ARM === "playwright" || ARM === "devtools")) {
  const serverArgs = ARM === "playwright"
    ? ["-y", "@playwright/mcp@0.0.79", "--headless", "--no-sandbox", "--user-data-dir", profileDir]
    : ["-y", "chrome-devtools-mcp@1.8.0", "--headless", "--no-usage-statistics", "--no-update-checks",
       "--user-data-dir", profileDir];
  const server = { command: "npx", args: serverArgs };
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
if (effectiveArm === "agent-browser-guided") {
  // Documented deviation for the +guidance arm: context the user could provide.
  prompt += "\n\nA few tips that may help: if a site shows a bot check or CAPTCHA, read what it asks for and complete it (type the code it shows, or tick the checkbox) instead of giving up or retrying blindly. If a page says it is checking your browser, wait for it to finish rather than refreshing. If you hit HTTP 429, wait the stated number of seconds before retrying. Prefer real page navigation over fetching URLs with curl when a site checks for bots.\n";
}
prompt += `\n\nThe site is running at ${baseUrl} .\n`;

const eventsPath = path.join(runDir, "events.jsonl");
const transcriptPath = path.join(runDir, "transcript.jsonl");
const streamPath = path.join(runDir, "stream.jsonl");
const runLog = path.join(runDir, "harness.log");
const log = (msg: string) => appendFileSync(runLog, `${new Date().toISOString()} ${msg}\n`);
const transcript = (obj: any) => appendFileSync(transcriptPath, JSON.stringify(obj) + "\n");
const slimEvent = (obj: any) => appendFileSync(eventsPath, JSON.stringify(obj) + "\n");

const textOf = (c: any): string =>
  Array.isArray(c) ? c.map((b) => (typeof b === "string" ? b : b?.text ?? "")).join("") : String(c ?? "");

const toolCounts: Record<string, number> = {};
const toolCalls: { tool: string; args: any }[] = [];
let assistantTurns = 0;
let lastEventAt = Date.now();
let lastAssistantText = "";
let usageIn = 0, usageOut = 0, usageCacheRead = 0;

function countTool(name: string, args: any, id: string = "") {
  toolCounts[name] = (toolCounts[name] ?? 0) + 1;
  toolCalls.push({ tool: name, args });
  transcript({ ts: Date.now(), type: "tool_start", toolName: name, toolCallId: id, args });
}

// ---- per-harness stream handling ------------------------------------------
// Normalized tool names keep score.py's conventions: shell -> "bash",
// file reads -> "read", edits/writes -> "edit"/"write". Native-only tools keep
// their own names (WebFetch, Task*, ...).
const OCC_TOOL_MAP: Record<string, string> = { Bash: "bash", Read: "read", Edit: "edit", Write: "write" };
const idToName: Record<string, string> = {};
let settledSeen = false;
let retriedEmpty = false;
let promptError: string | undefined;
let nativeTools: string[] | null = null;

function handlePiEvent(event: any) {
  switch (event.type) {
    case "tool_execution_start": {
      const name = event.toolName;
      toolCounts[name] = (toolCounts[name] ?? 0) + 1;
      toolCalls.push({ tool: name, args: event.args });
      transcript({ ts: Date.now(), type: "tool_start", toolName: name, toolCallId: event.toolCallId, args: event.args });
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
    case "agent_settled": {
      const first = !settledSeen;
      settledSeen = true;
      if (first && !retriedEmpty && Object.keys(toolCounts).length === 0 && lastAssistantText.trim() === "") {
        retriedEmpty = true;
        log("empty first turn; retrying prompt once");
        setTimeout(() => sendRpc({ id: "p2", type: "prompt", message: prompt }), 2000);
      }
      break;
    }
  }
}

function handleOccEvent(e: any) {
  const t = e.type;
  if (t === "system" && e.subtype === "init") {
    nativeTools = e.tools ?? null;
  } else if (t === "assistant") {
    assistantTurns++;
    const texts: string[] = [];
    for (const b of ((e.message ?? {}).content ?? []) as any[]) {
      if (!b || typeof b !== "object") continue;
      if (b.type === "text" && b.text) texts.push(String(b.text));
      else if (b.type === "tool_use") {
        const name = OCC_TOOL_MAP[String(b.name ?? "")] ?? String(b.name ?? "");
        idToName[String(b.id ?? "")] = name;
        countTool(name, b.input ?? {}, String(b.id ?? ""));
      }
    }
    // Per-call usage EXCLUDES cache tokens so occ matches pi's accounting
    // (score.py's tokens column is usage.input + usage.output, and pi's input
    // never includes cacheRead; adding cache reads here would inflate occ's
    // column vs pi on the same scoreboard). The `result` event below carries
    // the authoritative cumulative totals and overwrites these.
    const u = (e.message ?? {}).usage;
    if (u) {
      usageIn += u.input_tokens ?? 0;
      usageOut += u.output_tokens ?? 0;
      usageCacheRead += u.cache_read_input_tokens ?? 0;
    }
    const text = texts.join("\n").trim();
    if (text) lastAssistantText = text;
    transcript({ ts: Date.now(), type: "turn_end", text: text.slice(0, 8000), toolResults: [] });
  } else if (t === "user") {
    const content = (e.message ?? {}).content;
    for (const b of Array.isArray(content) ? content : []) {
      if (b && b.type === "tool_result") {
        const cid = String(b.tool_use_id ?? "");
        transcript({ ts: Date.now(), type: "tool_end", toolName: idToName[cid] ?? "tool", toolCallId: cid, isError: !!b.is_error, text: textOf(b.content).slice(0, 8000) });
      }
    }
  } else if (t === "result") {
    if (e.result) lastAssistantText = String(e.result);
    const ru = e.usage;
    if (ru) {
      // Authoritative cumulative usage for the whole run; overwrite the
      // per-call sums rather than adding to them.
      usageIn = ru.input_tokens ?? usageIn;
      usageOut = ru.output_tokens ?? usageOut;
      usageCacheRead = ru.cache_read_input_tokens ?? usageCacheRead;
    }
  }
}

function ocdxToolName(it: any): string | null {
  const ty = it?.type;
  if (ty === "command_execution") return "bash";
  if (ty === "file_change") return "edit";
  if (ty === "mcp_tool_call") {
    const inv = it?.invocation ?? it;
    return String(inv?.tool ?? inv?.server ?? "mcp_tool_call");
  }
  return null;
}
function ocdxCommandArgs(it: any): any {
  const cmd = it?.command;
  if (typeof cmd === "string") return { command: cmd };
  if (Array.isArray(cmd)) return { command: cmd.join(" ") };
  return {};
}

function handleOcdxEvent(e: any) {
  const t = e.type;
  const it = e.item ?? {};
  if (t === "item.started") {
    const name = ocdxToolName(it);
    if (name) countTool(name, ocdxCommandArgs(it), String(it.id ?? ""));
  } else if (t === "item.completed") {
    if (it.type === "command_execution") {
      transcript({ ts: Date.now(), type: "tool_end", toolName: "bash", toolCallId: String(it.id ?? ""), isError: it.exit_code != null && it.exit_code !== 0, text: String(it.aggregated_output ?? "").slice(0, 8000) });
    } else if (it.type === "file_change") {
      transcript({ ts: Date.now(), type: "tool_end", toolName: "edit", toolCallId: String(it.id ?? ""), isError: false, text: JSON.stringify(it.changes ?? []).slice(0, 8000) });
    } else if (it.type === "mcp_tool_call") {
      const id = String(it.id ?? "");
      transcript({ ts: Date.now(), type: "tool_end", toolName: idToName[id] ?? ocdxToolName(it) ?? "mcp_tool_call", toolCallId: id, isError: !!it.isError, text: JSON.stringify(it.result ?? {}).slice(0, 8000) });
    } else if (it.type === "agent_message") {
      assistantTurns++;
      const text = String(it.text ?? "").trim();
      if (text) lastAssistantText = text;
      transcript({ ts: Date.now(), type: "turn_end", text: text.slice(0, 8000), toolResults: [] });
    } else if (it.type === "error") {
      promptError = String(it.text ?? it.message ?? "error item");
    }
  } else if (t === "turn.completed") {
    // codex exec --json reports session-cumulative usage on turn.completed;
    // overwrite with the latest snapshot instead of summing running totals.
    // NOTE: turn.completed fires per turn (multiple per exec) and must NOT be
    // treated as session-done: lifecycle ends only on process exit or budget.
    const u = e.usage ?? {};
    usageIn = u.input_tokens ?? usageIn;
    usageOut = u.output_tokens ?? usageOut;
    usageCacheRead = u.cached_input_tokens ?? usageCacheRead;
  }
}

// ---- launch the live harness ----------------------------------------------
const versionProbeCmd = HARNESS === "occ" ? ["claude", "--version"]
  : HARNESS === "ocdx" ? ["codex", "--version"]
  : ["pi", "--version"];
const agentVersion = (spawnSync(versionProbeCmd[0], versionProbeCmd.slice(1), { encoding: "utf8", timeout: 60_000 }).stdout ?? "").trim().split("\n").pop() ?? "";

const childEnv: Record<string, string> = { ...(process.env as Record<string, string>) };
// Per-run browser CLI isolation for every harness (the CLIs are on PATH).
childEnv.AGENT_BROWSER_SESSION = `bb-${NONCE}`;
childEnv.AGENT_BROWSER_NAMESPACE = `bb-${NONCE}`;
childEnv.PLAYWRIGHT_CLI_SESSION = `bb-${NONCE}`;

let cmd: string[];
let rpcMode = false;
if (HARNESS === "pi" || HARNESS === "p") {
  rpcMode = true;
  cmd = [HARNESS, "--mode", "rpc", "--no-session", "--model", MODEL];
  if (HARNESS === "pi") {
    childEnv.PI_CODING_AGENT_DIR = PIHOME;
    delete childEnv.PI_CODING_AGENT_SESSION_DIR;
  } // p's wrapper owns its profile dir; overriding it would not be p's setup.
} else {
  const slug = MODEL.replace(/^openrouter\//, "");
  if (HARNESS === "occ") {
    const claudeHome = path.join(runDir, "claude-home");
    mkdirSync(claudeHome, { recursive: true });
    childEnv.CLAUDE_CONFIG_DIR = claudeHome;
    cmd = ["occ", "--model", slug, "--verbose", "--output-format", "stream-json", "--print", prompt];
  } else {
    const codexHome = path.join(runDir, "codex-home");
    mkdirSync(codexHome, { recursive: true });
    const managed = path.join(process.env.HOME ?? "", ".pi", "agent-ocdx", "codex");
    for (const f of ["config.toml", "models.json"]) {
      if (existsSync(path.join(managed, f))) cpSync(path.join(managed, f), path.join(codexHome, f));
    }
    if (!existsSync(path.join(codexHome, "config.toml"))) {
      throw new Error(`missing ${managed}/config.toml — run the pi-setup installer`);
    }
    childEnv.CODEX_HOME = codexHome;
    cmd = ["ocdx", "--model", slug, "exec", "--skip-git-repo-check", "--json", prompt];
  }
}

const child = spawn(cmd[0], cmd.slice(1), {
  cwd: workDir,
  env: childEnv,
  stdio: ["pipe", "pipe", "pipe"],
  detached: true, // own process group: budget kills must take the whole tree
});
const stderrStream = createWriteStream(path.join(runDir, "cli-stderr.log"));
child.stderr?.pipe(stderrStream);
const rawStream = createWriteStream(streamPath);

function sendRpc(obj: any) {
  try { child.stdin?.write(JSON.stringify(obj) + "\n"); } catch (e: any) { log(`stdin write error: ${e?.message}`); }
}

let childExited: { code: number | null } | null = null;
child.on("exit", (code) => { childExited = { code }; });

let buf = "";
function consumeLine(lineRaw: string) {
  const line = lineRaw.replace(/\r$/, "");
  if (!line.trim()) return;
  let event: any;
  try { event = JSON.parse(line); } catch { return; }
  lastEventAt = Date.now();
  if (rpcMode && event.type === "response") {
    if (event.command === "prompt" && event.success === false) {
      promptError = String(event.error ?? "prompt rejected");
      log(`prompt error: ${promptError}`);
    }
    slimEvent({ ts: Date.now(), type: "rpc_response", command: event.command, success: event.success });
    return;
  }
  if (rpcMode) handlePiEvent(event);
  else if (HARNESS === "occ") handleOccEvent(event);
  else handleOcdxEvent(event);
  if (rpcMode) {
    const slim: any = { ts: Date.now(), type: event.type };
    if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
      slim.kind = "text_delta";
      slim.len = event.assistantMessageEvent.delta?.length ?? 0;
    }
    slimEvent(slim);
  } else {
    slimEvent({ ts: Date.now(), type: event.type });
  }
}
child.stdout?.setEncoding("utf8");
child.stdout?.on("data", (chunk: string) => {
  rawStream.write(chunk);
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
log(`task=${TASK} harness=${HARNESS} arm=${effectiveArm} agentVersion=${agentVersion} model=${MODEL} seed=${SEED} budget=${BUDGET_S}s site=${baseUrl} workdir=${workDir}`);
if (rpcMode) sendRpc({ id: "p1", type: "prompt", message: prompt });

// ---- quiescence / budget loop ----------------------------------------------
function killGroup(sig: NodeJS.Signals) {
  try { process.kill(-child.pid!, sig); } catch { try { child.kill(sig); } catch {} }
}
let exitReason = "budget";
while (Date.now() - t0 < BUDGET_S * 1000) {
  await new Promise((r) => setTimeout(r, 2000));
  if (childExited) break;
  const idleMs = Date.now() - lastEventAt;
  if (rpcMode && settledSeen && idleMs >= QUIESCE_MS) { exitReason = "settled"; break; }
  // One-shot CLIs (occ/ocdx) are never killed on stdout silence: their turn
  // boundaries are not session boundaries, and a >=5s API wait mid-run is
  // normal. Their loop ends on process exit (above) or budget only.
}
if (exitReason === "budget") log("budget reached");
else if (childExited && exitReason !== "settled") log(`cli exited early code=${childExited.code}`);
else log(`settled after ${Math.round((Date.now() - t0) / 1000)}s`);
if (childExited && exitReason === "budget" && Date.now() - t0 < BUDGET_S * 1000 - 3000) {
  exitReason = childExited.code === 0 ? "settled" : `cli_rc_${childExited.code}`;
}

if (!childExited) {
  if (rpcMode) { sendRpc({ type: "abort" }); try { child.stdin?.end(); } catch {} }
  killGroup("SIGTERM");
  await new Promise<void>((resolve) => {
    const t = setTimeout(() => { killGroup("SIGKILL"); resolve(); }, 5000);
    child.on("exit", () => { clearTimeout(t); resolve(); });
  });
}

const finalText = lastAssistantText;

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
  task: TASK, arm: effectiveArm, model: MODEL, harness: HARNESS, seed: SEED, nonce: NONCE,
  baseUrl, budgetSeconds: BUDGET_S, startedAt, endedAt,
  durationMs: Date.now() - t0, exitReason, promptError,
  assistantTurns, toolCounts, toolCalls, packages,
  nativeTools, agentVersion, piVersion: agentVersion,
  usage: { input: usageIn, output: usageOut, cacheRead: usageCacheRead },
  siteSummary, finalText: finalText.slice(0, 6000),
  mcpCleanupKills: killed,
};
writeFileSync(path.join(runDir, "run.json"), JSON.stringify(run, null, 2));
log(`done: ${JSON.stringify({ exitReason, durationMs: run.durationMs, toolCounts })}`);
console.log(`[${HARNESS}/${effectiveArm}/${TASK}] finished (${exitReason}) in ${Math.round(run.durationMs / 1000)}s`);
process.exit(0);
