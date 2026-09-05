#!/usr/bin/env bun
/**
 * Cross-platform installer. install.sh and install.ps1 bootstrap Bun, locate
 * this repository, and exec this file. Do not run it against a random
 * directory: PI_SETUP_SRC (or this file's repo root) must contain forks/.
 */
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const WIN = process.platform === "win32";
const HOME = homedir();
const SRC_DIR = process.env.PI_SETUP_SRC
  ? process.env.PI_SETUP_SRC
  : join(dirname(fileURLToPath(import.meta.url)), "..");

const versions = JSON.parse(readFileSync(join(SRC_DIR, "lib/versions.json"), "utf8"));
const vendor = JSON.parse(readFileSync(join(SRC_DIR, "vendor.json"), "utf8"));
const FORKS = Object.keys(vendor.forks);
const WF_FORK = "pi-dynamic-workflows-safe";
// Skills are not Pi packages: they need no package.json and no settings.json entry, so
// they live in skills/ here and in the agent directories' own skills/ there, not under
// local/ (three of them used to be skills-only packages; see skills/README.md). Only the
// named directories are managed - anything else a user put in these skills directories
// is left alone. piwf has its own agent directory, so it gets its own copies; the lean
// p profile runs --no-skills and gets none.
const SKILLS = ["agent-browser-cli", "unslop", "update-pi-setup"];
// Skills-only packages these skills replaced: their directories are removed so the
// doctor's unknown-package check stays quiet.
const RETIRED_PKG_DIRS = ["pi-setup-maintenance", "unslop", "pi-browser-cli"];
const MODEL_SCOPE = [
  "openrouter/deepseek/deepseek-v4-flash-0731",
  "openrouter/deepseek/deepseek-v4-pro-0813",
  "openrouter/z-ai/glm-5.3",
  "openrouter/z-ai/glm-5.3-flash",
  "openrouter/moonshotai/kimi-k3",
  "openrouter/qwen/qwen3.8-flash",
  "openrouter/qwen/qwen3.8-max",
  "openai/gpt-5.6-sol",
  "openai/gpt-5.6-terra",
  "openai/gpt-5.6-luna",
];

function log(msg) {
  console.log(`\n==> ${msg}`);
}
function warn(msg) {
  console.error(`\nWARNING: ${msg}`);
}
function fail(msg) {
  console.error(`\nERROR: ${msg}`);
  process.exit(1);
}

function which(name) {
  const pathEnv = process.env.PATH || "";
  const exts = WIN ? (process.env.PATHEXT || ".EXE;.CMD;.BAT").split(";").concat("") : [""];
  for (const dir of pathEnv.split(delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = join(dir, name + ext);
      if (existsSync(candidate)) return candidate;
    }
  }
  return "";
}

function bunCandidates(bunInstall) {
  const names = WIN ? ["bun.exe", "bun"] : ["bun"];
  const out = [];
  const fromPath = which("bun");
  if (fromPath) out.push(fromPath);
  for (const name of names) out.push(join(bunInstall, "bin", name));
  return out;
}

function findBun(bunInstall) {
  for (const c of bunCandidates(bunInstall)) {
    if (c && existsSync(c)) return c;
  }
  return "";
}

function run(bin, args, opts = {}) {
  const spawnOpts = {
    encoding: "utf8",
    stdio: opts.stdio ?? "inherit",
    cwd: opts.cwd,
    env: opts.env ?? process.env,
    windowsHide: true,
    shell: opts.shell ?? false,
  };
  if (WIN && /\.(cmd|bat)$/i.test(String(bin))) {
    const quoted = [bin, ...args].map((a) => (/[ \t"]/.test(a) ? `"${a.replaceAll('"', '""')}"` : a)).join(" ");
    const r = spawnSync(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", quoted], spawnOpts);
    return r.status ?? 1;
  }
  const r = spawnSync(bin, args, spawnOpts);
  return r.status ?? 1;
}

function readTemplate(name) {
  return readFileSync(join(SRC_DIR, "lib", "wrappers", name), "utf8");
}

function writeExec(dest, body) {
  if (existsSync(dest)) rmSync(dest, { force: true });
  const text = body.endsWith("\n") ? body : body + "\n";
  const data = dest.endsWith(".cmd") ? text.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n") : text.replace(/\r\n/g, "\n");
  writeFileSync(dest, data);
  if (!WIN) {
    try {
      chmodSync(dest, 0o755);
    } catch {
      /* NTFS or no-op */
    }
  }
}

function posixPath(p) {
  return p.replace(/\\/g, "/");
}

function windowsPiRuntimeDir() {
  return join(HOME, ".local", "lib", "pi-coding-agent");
}

function copyJsonFiles(srcDir, destDir) {
  if (!existsSync(srcDir)) return;
  mkdirSync(destDir, { recursive: true });
  for (const name of readdirSync(srcDir)) {
    if (!name.endsWith(".json")) continue;
    cpSync(join(srcDir, name), join(destDir, name));
  }
}

/**
 * PowerShell in Windows Terminal resolves `pi` to pi.cmd, which starts cmd.exe
 * and then Bun over thousands of JS files. A compiled pi.exe next to Pi's
 * package.json/theme is a single image, and a profile function skips PATH
 * search plus the .cmd hop.
 */
function installWindowsPiBinary(bunBin, piRoot) {
  const runtimeDir = windowsPiRuntimeDir();
  const exe = join(runtimeDir, "pi.exe");
  const cli = join(piRoot, "dist", "bun", "cli.js");
  if (!existsSync(cli)) fail(`Missing Pi CLI at ${cli}`);
  mkdirSync(runtimeDir, { recursive: true });
  log("Compiling Pi to a Windows executable");
  const st = run(bunBin, ["build", "--compile", cli, "--outfile", exe]);
  if (st !== 0) {
    warn("Could not compile pi.exe; PowerShell will keep using pi.cmd (slower startup).");
    return "";
  }
  cpSync(join(piRoot, "package.json"), join(runtimeDir, "package.json"));
  copyJsonFiles(join(piRoot, "dist", "modes", "interactive", "theme"), join(runtimeDir, "theme"));
  const assets = join(piRoot, "dist", "modes", "interactive", "assets");
  if (existsSync(assets)) cpSync(assets, join(runtimeDir, "assets"), { recursive: true });
  const exportHtml = join(piRoot, "dist", "core", "export-html");
  if (existsSync(exportHtml)) {
    mkdirSync(join(runtimeDir, "export-html"), { recursive: true });
    for (const name of ["template.html", "template.css", "template.js"]) {
      const src = join(exportHtml, name);
      if (existsSync(src)) cpSync(src, join(runtimeDir, "export-html", name));
    }
    const vendorDir = join(exportHtml, "vendor");
    if (existsSync(vendorDir)) cpSync(vendorDir, join(runtimeDir, "export-html", "vendor"), { recursive: true });
  }
  return exe;
}

function addPowerShellPiCommand(profilePath, exePath, cmdFallback) {
  const startMarker = "# pi-setup: pi-command";
  const endMarker = "# pi-setup: end-pi-command";
  const exe = exePath.replace(/'/g, "''");
  const cmd = cmdFallback.replace(/'/g, "''");
  const block = `${startMarker}
function pi {
  $leanDir = Join-Path $env:USERPROFILE '.pi\\agent-p'
  $wfDir = Join-Path $env:USERPROFILE '.pi\\agent-wf'
  if ($env:PI_CODING_AGENT_DIR -eq $leanDir -or $env:PI_CODING_AGENT_DIR -eq $wfDir) {
    Remove-Item Env:PI_CODING_AGENT_DIR, Env:PI_CODING_AGENT_SESSION_DIR, Env:PI_SKIP_VERSION_CHECK -ErrorAction SilentlyContinue
  }
  $exe = '${exe}'
  if (Test-Path -LiteralPath $exe) { & $exe @args; return }
  & '${cmd}' @args
}
${endMarker}
`;
  mkdirSync(dirname(profilePath), { recursive: true });
  let prev = "";
  try {
    prev = readFileSync(profilePath, "utf8");
  } catch {
    prev = "";
  }
  prev = prev.replace(/\r?\n?# pi-setup: pi-command\r?\n[\s\S]*?# pi-setup: end-pi-command\r?\n?/g, "\n");
  prev = prev.replace(/\r?\n?# pi-setup: pi-command\r?\nfunction pi \{[\s\S]*?\n\}\r?\n?/g, "\n");
  writeFileSync(profilePath, `${prev.trimEnd()}\n\n${block}`);
}

/**
 * Pi loads TypeScript extensions through jiti, which on Windows can take many
 * seconds per package. Compile each TypeScript `vendor.json` live entry to a
 * sibling .js file in the same folder so startup imports stay native and Pi's
 * extension listing still uses the `extensions/<name>/` directory name.
 */
function compileTsToJs(input, out, bunBin, cwd) {
  mkdirSync(dirname(out), { recursive: true });
  return run(bunBin, [
    "build",
    input,
    "--outfile",
    out,
    "--target",
    "bun",
    "--format",
    "esm",
    "--packages",
    "external",
  ], { cwd });
}

function compileForkExtension(dest, fork, bunBin) {
  const live = vendor.forks[fork]?.live;
  if (typeof live !== "string" || !live.endsWith(".ts")) return;
  const input = join(dest, live);
  if (!existsSync(input)) fail(`Missing extension entry for ${fork}: ${input}`);
  const out = join(dest, live.replace(/\.ts$/i, ".js"));
  if (compileTsToJs(input, out, bunBin, dest) !== 0) fail(`bun build failed for ${fork} (${live})`);
}

/**
 * Apply the pinned Pi AI reasoning fix with patch(1). macOS and Linux run patch
 * directly; on Windows patch(1) ships inside Git Bash, which Pi needs for its bash
 * tool anyway. Idempotent: the verifier accepts an already-patched tree.
 */
function applyPiAiReasoningPatch(bunBin, piAiRoot, gitBash) {
  const patchFile = join(SRC_DIR, "patches", `pi-ai@${versions.piAi}-reasoning-details.patch`);
  if (!existsSync(patchFile)) fail(`Missing Pi reasoning patch: ${patchFile}`);
  const verifier = join(SRC_DIR, "bin", "verify-pi-ai-reasoning-fix");
  if (!existsSync(verifier)) fail("Missing Pi reasoning verifier.");
  const installed = JSON.parse(readFileSync(join(piAiRoot, "package.json"), "utf8")).version;
  if (installed !== versions.piAi) {
    fail(`Expected @earendil-works/pi-ai ${versions.piAi}, found ${installed}; refusing to apply a version-specific patch.`);
  }
  if (run(bunBin, [verifier, piAiRoot], { stdio: "ignore" }) === 0) {
    console.log("    reasoning-details patch already present");
    return;
  }
  const quotedRoot = piAiRoot.replace(/'/g, "'\\''");
  const quotedPatch = patchFile.replace(/'/g, "'\\''");
  const script = `set -e; patch --dry-run --batch --forward -d '${quotedRoot}' -p1 < '${quotedPatch}' >/dev/null && patch --batch --forward -d '${quotedRoot}' -p1 < '${quotedPatch}'`;
  const status = WIN
    ? run(gitBash, ["-lc", script], { stdio: "ignore" })
    : run("bash", ["-c", script], { stdio: "ignore" });
  if (status !== 0) {
    fail(`The Pi reasoning patch does not apply cleanly to @earendil-works/pi-ai ${versions.piAi}. Refusing a partial install.`);
  }
  if (run(bunBin, [verifier, piAiRoot], { stdio: "inherit" }) !== 0) {
    fail("The Pi reasoning patch was applied but the verifier rejected the result.");
  }
}

function copyFork(src, dest) {
  rmSync(dest, { recursive: true, force: true });
  mkdirSync(dest, { recursive: true });
  cpSync(src, dest, {
    recursive: true,
    filter: (p) => {
      const rel = relative(src, p);
      if (!rel || rel === ".") return true;
      const parts = rel.split(sep);
      return !parts.includes("node_modules") && !parts.includes(".git") && parts[parts.length - 1] !== "bun.lock";
    },
  });
}

function sharePath(target, dest, dir) {
  rmSync(dest, { recursive: true, force: true });
  if (!dir && !existsSync(target)) writeFileSync(target, "{}\n");
  try {
    symlinkSync(target, dest, dir ? (WIN ? "junction" : "dir") : "file");
  } catch {
    if (dir) cpSync(target, dest, { recursive: true });
    else cpSync(target, dest);
    if (WIN) {
      warn(
        `${dest} is a copy of ${target}, not a link. Enable Windows Developer Mode so the lean profile shares auth and models, then re-run the installer.`,
      );
    }
  }
}

function addUnixPathLine(file) {
  const line = 'export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"';
  mkdirSync(dirname(file), { recursive: true });
  let prev = "";
  try {
    prev = readFileSync(file, "utf8");
  } catch {
    prev = "";
  }
  if (prev.split(/\r?\n/).includes(line)) return;
  writeFileSync(file, prev + (prev.endsWith("\n") || prev === "" ? "" : "\n") + "\n" + line + "\n");
}

function addWindowsUserPath(dirs) {
  const escaped = dirs.map((d) => `'${d.replace(/'/g, "''")}'`).join(",");
  const script = `
$dirs = @(${escaped})
$user = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $user) { $user = '' }
$parts = @($user -split ';' | Where-Object { $_ -ne '' })
$changed = $false
foreach ($d in $dirs) {
  $found = $false
  foreach ($p in $parts) {
    if ([string]::Equals($p, $d, 'OrdinalIgnoreCase')) { $found = $true; break }
  }
  if (-not $found) { $parts = @($d) + $parts; $changed = $true }
}
if ($changed) {
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}
`;
  const pathResult = spawnSync("powershell.exe", ["-NoProfile", "-Command", script], {
    encoding: "utf8",
    windowsHide: true,
  });
  if ((pathResult.status ?? 1) !== 0) {
    warn(`Could not update the user PATH (${pathResult.stderr || pathResult.error || "powershell exited non-zero"}). Add ${dirs.join(" and ")} to PATH manually.`);
  }
}

function setWindowsUserEnv(name, value) {
  const script = `[Environment]::SetEnvironmentVariable('${name.replace(/'/g, "''")}', '${value.replace(/'/g, "''")}', 'User')`;
  const r = spawnSync("powershell.exe", ["-NoProfile", "-Command", script], {
    encoding: "utf8",
    windowsHide: true,
  });
  if ((r.status ?? 1) !== 0) {
    warn(`Could not set ${name} (${r.stderr || r.error || "powershell exited non-zero"}).`);
  }
}

function addPowerShellPathLine(profilePath, dirs) {
  const line = `$env:Path = "${dirs.join(";")};" + $env:Path`;
  mkdirSync(dirname(profilePath), { recursive: true });
  let prev = "";
  try {
    prev = readFileSync(profilePath, "utf8");
  } catch {
    prev = "";
  }
  if (prev.includes(".local\\bin") || prev.includes(".local/bin")) return;
  writeFileSync(profilePath, prev + (prev.endsWith("\n") || prev === "" ? "" : "\n") + "\n" + line + "\n");
}

/** WSL's System32 bash.exe is not the Git Bash Pi needs for its bash tool. */
function isUsableWindowsBash(p) {
  if (!p) return false;
  const normalized = String(p).replace(/\//g, "\\").toLowerCase();
  if (normalized.includes("\\windows\\system32\\bash.exe")) return false;
  if (normalized.includes("\\windows\\sysnative\\bash.exe")) return false;
  if (normalized.includes("\\windows\\syswow64\\bash.exe")) return false;
  return true;
}

function findGitBash() {
  const candidates = [
    process.env.PI_BASH,
    process.env.GIT_BASH,
    join("C:", "Program Files", "Git", "bin", "bash.exe"),
    join("C:", "Program Files", "Git", "usr", "bin", "bash.exe"),
    join("C:", "Program Files (x86)", "Git", "bin", "bash.exe"),
  ].filter(Boolean);
  const git = which("git");
  if (git) {
    const gitDir = dirname(git);
    candidates.push(join(gitDir, "bash.exe"), join(gitDir, "..", "bin", "bash.exe"), join(gitDir, "..", "usr", "bin", "bash.exe"));
  }
  const fromPath = which("bash");
  if (fromPath && /git/i.test(fromPath)) candidates.push(fromPath);
  for (const c of candidates) {
    if (c && existsSync(c) && isUsableWindowsBash(c)) return c;
  }
  return "";
}

function writeConfig({
  mainPath,
  pPath,
  wfPath,
  sttPath,
  npmPkgPath,
  pNpmPkgPath,
  wfNpmPkgPath,
  piVersion,
  keybindingsSrcPath,
  mainKeybindsPath,
  pKeybindsPath,
  wfKeybindsPath,
  compactionSrcPath,
  modelsStorePath,
  modelTiersSrcPath,
  modelTiersDestPath,
  shellPath,
}) {
  const read = (p) => (existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : {});
  const writeJson = (p, value) => writeFileSync(p, JSON.stringify(value, null, 2) + "\n");

  const main = read(mainPath);
  main.lastChangelogVersion ??= piVersion;
  main.defaultThinkingLevel = "medium";
  // Provider and model decide which credentials Pi uses, so they are seeded and then left
  // alone. Forcing them reverted a deliberate choice on every install: one machine here runs
  // openai-codex, and a reinstall would have silently pointed it at plain openai auth.
  main.defaultProvider ??= "openrouter";
  main.defaultModel ??= "z-ai/glm-5.3-flash";
  main.theme ??= "dark";
  delete main.quietStartup;
  if (shellPath) main.shellPath ??= shellPath;

  const compactionPolicy = read(compactionSrcPath);
  const contextWindowFor = (modelId) => {
    if (!modelId) return undefined;
    for (const provider of Object.values(read(modelsStorePath))) {
      for (const model of provider?.models ?? []) {
        if (model?.id === modelId && typeof model.contextWindow === "number") return model.contextWindow;
      }
    }
    return undefined;
  };
  const targetReserve = (settings) => {
    const floor = compactionPolicy.minReserveTokens ?? 16384;
    const window = contextWindowFor(settings.defaultModel);
    let target = compactionPolicy.reserveTokens ?? floor;
    if (typeof window === "number" && typeof compactionPolicy.maxFractionOfWindow === "number") {
      target = Math.min(target, Math.floor(window * compactionPolicy.maxFractionOfWindow));
    }
    return Math.max(floor, target);
  };
  const applyCompaction = (settings) => {
    const compaction = { ...(settings.compaction ?? {}) };
    const current = typeof compaction.reserveTokens === "number" ? compaction.reserveTokens : 0;
    compaction.reserveTokens = Math.max(current, targetReserve(settings));
    settings.compaction = compaction;
  };
  applyCompaction(main);

  // Every extension is a hardened local fork. The upstream npm identities are dropped
  // so a previously npm-installed copy cannot shadow the fork.
  //
  // The browser default is a CLI plus a skill, not a tool: evals/browser on the
  // browser-eval branch benchmarked six surfaces and found the CLI+skill arms matched or
  // beat every extension arm on outcome at roughly half the calls and tokens.
  // pi-agent-browser-native-safe therefore stays installed but is only loaded when the
  // install is run with PI_SETUP_BROWSER_TOOL=1; the managed list below still names it,
  // so a stale entry from before that change is removed on reinstall.
  const wanted = FORKS.map((name) => `local/${name}`);
  if (process.env.PI_SETUP_BROWSER_TOOL !== "1") {
    const idx = wanted.indexOf("local/pi-agent-browser-native-safe");
    if (idx !== -1) wanted.splice(idx, 1);
  }
  const managed = new Set([
    "pi-voice-stt",
    "pi-agent-browser-native",
    "@quintinshaw/pi-dynamic-workflows",
    "pi-continue",
    "pi-process-monitor",
    ...FORKS,
    // Retired as packages: agent-browser-cli, update-pi-setup, and unslop are now plain
    // skills installed from skills/ into the agent directories. Their identities stay
    // here so stale settings entries and npm copies are removed on reinstall.
    "pi-setup-maintenance",
    "unslop",
    "pi-browser-cli",
    "pi-btw",
    "pi-render-btw",
    "pi-btw-inline",
    "pi-continue-safe",
  ]);
  const identity = (entry) => {
    const source = typeof entry === "string" ? entry : entry?.source;
    if (typeof source !== "string") return "";
    let spec = source.replace(/^npm:/, "");
    if (spec.startsWith("local/")) return spec.slice("local/".length);
    if (spec.startsWith("@")) return spec.split("@").slice(0, 2).join("@");
    return spec.split("@")[0];
  };
  const mainWanted = wanted.filter((w) => w !== `local/${WF_FORK}`);
  main.packages = [...(main.packages ?? []).filter((entry) => !managed.has(identity(entry))), ...mainWanted];
  main.enabledModels = MODEL_SCOPE;
  writeJson(mainPath, main);

  const full = read(wfPath);
  full.lastChangelogVersion ??= main.lastChangelogVersion;
  full.defaultThinkingLevel ??= main.defaultThinkingLevel;
  full.defaultProvider ??= main.defaultProvider;
  full.defaultModel ??= main.defaultModel;
  full.theme ??= main.theme;
  delete full.quietStartup;
  if (shellPath) full.shellPath ??= shellPath;
  full.packages = [...(full.packages ?? []).filter((entry) => !managed.has(identity(entry))), ...wanted];
  full.enabledModels = MODEL_SCOPE;
  applyCompaction(full);
  writeJson(wfPath, full);

  const lean = read(pPath);
  lean.lastChangelogVersion ??= main.lastChangelogVersion;
  lean.defaultThinkingLevel ??= main.defaultThinkingLevel;
  lean.defaultProvider ??= main.defaultProvider;
  lean.defaultModel ??= main.defaultModel;
  lean.theme ??= main.theme;
  lean.quietStartup = true;
  lean.enabledModels = MODEL_SCOPE;
  if (shellPath) lean.shellPath ??= shellPath;
  applyCompaction(lean);
  writeJson(pPath, lean);

  const managedKeys = read(keybindingsSrcPath);
  for (const p of [mainKeybindsPath, pKeybindsPath, wfKeybindsPath]) {
    if (!p) continue;
    writeJson(p, { ...read(p), ...managedKeys });
  }

  const stt = read(sttPath);
  stt.keybind = ["alt+p", "\u03c0"];
  stt.provider = {
    type: "openai",
    model: "gpt-4o-mini-transcribe",
    apiKeyEnv: "OPENAI_API_KEY",
    language: "auto",
  };
  writeJson(sttPath, stt);

  let removed = false;
  for (const p of [npmPkgPath, pNpmPkgPath, wfNpmPkgPath]) {
    if (!p) continue;
    const pkg = read(p);
    const deps = pkg.dependencies ?? {};
    for (const name of Object.keys(deps)) {
      if (managed.has(name)) {
        delete deps[name];
        removed = true;
      }
    }
    pkg.private = true;
    pkg.dependencies = deps;
    writeJson(p, pkg);
  }
  if (removed) console.log("    pruned npm-installed extension copies");

  // Subagent model routing for pi-dynamic-workflows (the `piwf` profile). The file lives
  // at ~/.pi/workflows/model-tiers.json, outside any agent dir, and is read once per
  // workflow run. Seeded only when absent: like defaultProvider/defaultModel, tier routing
  // is a deliberate choice the user may re-point via /workflows-models, so a reinstall must
  // not clobber it. A missing file would otherwise make every untagged agent fall back to
  // the session's main model, which is exactly the single-vs-subagent split this seeds.
  if (modelTiersDestPath && !existsSync(modelTiersDestPath)) {
    mkdirSync(dirname(modelTiersDestPath), { recursive: true });
    const tiers = read(modelTiersSrcPath);
    writeFileSync(modelTiersDestPath, JSON.stringify({ tiers: tiers.tiers }, null, 2) + "\n");
    if (!WIN) {
      try {
        chmodSync(modelTiersDestPath, 0o600);
      } catch {
        /* ignore */
      }
    }
  }
}

function install() {
if (!existsSync(join(SRC_DIR, "forks"))) {
  fail(`Could not find forks/ in ${SRC_DIR}.`);
}

const bunInstall = process.env.BUN_INSTALL || join(HOME, ".bun");
const bunBin = findBun(bunInstall);
if (!bunBin) fail("Bun is not installed. Run install.sh or install.ps1, which bootstrap it.");

const mainDir = process.env.PI_CODING_AGENT_DIR || join(HOME, ".pi", "agent");
const pDir = join(HOME, ".pi", "agent-p");
const wfDir = join(HOME, ".pi", "agent-wf");
const localBin = join(HOME, ".local", "bin");
const npmDir = join(mainDir, "npm");
const localPkgDir = join(mainDir, "local");
const bunBinDir = join(bunInstall, "bin");
// Needed early: the Pi AI reasoning patch is applied through Git Bash's patch(1) on Windows.
const gitBash = WIN ? findGitBash() : "";

mkdirSync(localBin, { recursive: true });
mkdirSync(join(mainDir, "bin"), { recursive: true });
mkdirSync(join(mainDir, "p"), { recursive: true });
mkdirSync(npmDir, { recursive: true });
mkdirSync(localPkgDir, { recursive: true });
mkdirSync(pDir, { recursive: true });
mkdirSync(join(pDir, "npm"), { recursive: true });
mkdirSync(wfDir, { recursive: true });
mkdirSync(join(wfDir, "npm"), { recursive: true });

process.env.PATH = `${localBin}${delimiter}${bunBinDir}${delimiter}${process.env.PATH || ""}`;
process.env.BUN_INSTALL = bunInstall;

log("Installing Pi and agent-browser with Bun");
const addStatus = run(bunBin, [
  "--use-system-ca",
  "add",
  "--global",
  `@earendil-works/pi-coding-agent@${versions.pi}`,
  `@earendil-works/pi-ai@${versions.piAi}`,
  // pi-coding-agent 0.85.0 imports this from its Bun entrypoint graph but does not
  // declare it as a dependency (the npm bundle embeds it); without this pin every
  // `pi` invocation fails to load. See the comment in lib/versions.json.
  `@earendil-works/pi-server@${versions.piServer}`,
  `agent-browser@${versions.agentBrowser}`,
]);
if (addStatus !== 0) fail("bun add --global failed.");

const piRoot = join(bunInstall, "install", "global", "node_modules", "@earendil-works", "pi-coding-agent");
const agentBrowserRoot = join(bunInstall, "install", "global", "node_modules", "agent-browser");
if (!existsSync(join(piRoot, "dist", "bun", "cli.js"))) {
  fail(`Could not find Pi's Bun entrypoint at ${join(piRoot, "dist", "bun", "cli.js")}`);
}
if (!existsSync(join(agentBrowserRoot, "bin", "agent-browser.js"))) {
  fail(`Could not find agent-browser at ${agentBrowserRoot}`);
}

log(`Applying the Pi AI ${versions.piAi} reasoning-details fix`);
applyPiAiReasoningPatch(bunBin, join(bunInstall, "install", "global", "node_modules", "@earendil-works", "pi-ai"), gitBash);

// The npm entrypoint (dist/bundle/cli.js) loads pi-ai from a bundled chunk,
// not from node_modules, so the library patch above does not cover it. Apply
// the same historical-replay normalization to the bundle (idempotent,
// version-guarded to the pin in lib/versions.json).
log("Applying the reasoning-details fix to Pi's npm bundle entrypoint");
if (run(bunBin, [join(SRC_DIR, "bin", "patch-pi-bundle"), piRoot]) !== 0) {
  fail("bin/patch-pi-bundle failed; refusing to leave the npm entrypoint unpatched.");
}

log("Installing hardened extension forks as Pi local packages");
for (const fork of FORKS) {
  const src = join(SRC_DIR, "forks", fork);
  if (!existsSync(src) || !statSync(src).isDirectory()) fail(`Missing fork: ${src}`);
  const dest = join(localPkgDir, fork);
  copyFork(src, dest);
  let hasDeps = false;
  try {
    const pkg = JSON.parse(readFileSync(join(dest, "package.json"), "utf8"));
    hasDeps = Object.keys(pkg.dependencies ?? {}).length > 0;
  } catch {
    hasDeps = false;
  }
  if (hasDeps) {
    console.log(`    installing dependencies for ${fork}`);
    const st = run(bunBin, ["install", "--omit=dev", "--omit=peer", "--silent"], { cwd: dest });
    if (st !== 0) fail(`bun install failed for ${fork}`);
  }
  compileForkExtension(dest, fork, bunBin);
}

log("Installing first-party skills into the agent directories");
for (const skill of SKILLS) {
  const skillSrc = join(SRC_DIR, "skills", skill, "SKILL.md");
  if (!existsSync(skillSrc)) fail(`Missing skill: ${skillSrc}`);
  for (const destRoot of [join(mainDir, "skills"), join(wfDir, "skills")]) {
    const dest = join(destRoot, skill);
    rmSync(dest, { recursive: true, force: true });
    mkdirSync(dest, { recursive: true });
    cpSync(skillSrc, join(dest, "SKILL.md"));
  }
}

// Retire the skills-only packages these skills replaced. Their settings entries are
// stripped by the config writer (the managed set still names them); this removes the
// installed package directories themselves so the doctor's unknown-package check
// stays quiet.
for (const retired of RETIRED_PKG_DIRS) {
  rmSync(join(localPkgDir, retired), { recursive: true, force: true });
}

log("Installing the conditional MLX extension");
const mlxSrc = join(SRC_DIR, "extensions", "mlx");
if (!existsSync(mlxSrc) || !statSync(mlxSrc).isDirectory()) fail(`Missing extension: ${mlxSrc}`);
const mlxDest = join(mainDir, "extensions", "mlx");
rmSync(join(mainDir, "extensions", "mlx.ts"), { force: true });
copyFork(mlxSrc, mlxDest);
const mlxTs = join(mlxDest, "index.ts");
if (!existsSync(mlxTs)) fail(`Missing MLX entry: ${mlxTs}`);
if (compileTsToJs(mlxTs, join(mlxDest, "index.js"), bunBin, mlxDest) !== 0) {
  fail("bun build failed for extensions/mlx/index.ts");
}

const posixMain = posixPath(mainDir);
for (const cli of ["config", "doctor"]) {
  const target = join(localPkgDir, "pi-agent-browser-native-safe", "scripts", `${cli}.mjs`);
  if (!existsSync(target)) continue;
  writeExec(
    join(localBin, `pi-agent-browser-${cli}`),
    readTemplate("pi-agent-browser-cli.sh").replaceAll("__TARGET__", posixPath(target)),
  );
  if (WIN) {
    writeExec(
      join(localBin, `pi-agent-browser-${cli}.cmd`),
      readTemplate("pi-agent-browser-cli.cmd").replaceAll("__TARGET__", target),
    );
  }
}

writeExec(join(localBin, "pi"), readTemplate("pi.sh"));
writeExec(join(localBin, "agent-browser"), readTemplate("agent-browser.sh"));
writeExec(join(localBin, "p"), readTemplate("p.sh").replaceAll("__MAIN_DIR__", posixMain));
writeExec(join(localBin, "piwf"), readTemplate("piwf.sh").replaceAll("__MAIN_DIR__", posixMain));
if (WIN) {
  writeExec(join(localBin, "pi.cmd"), readTemplate("pi.cmd"));
  writeExec(join(localBin, "agent-browser.cmd"), readTemplate("agent-browser.cmd"));
  writeExec(join(localBin, "p.cmd"), readTemplate("p.cmd").replaceAll("__MAIN_DIR__", mainDir));
  writeExec(join(localBin, "piwf.cmd"), readTemplate("piwf.cmd").replaceAll("__MAIN_DIR__", mainDir));
  const piExe = installWindowsPiBinary(bunBin, piRoot);
  if (piExe) {
    const cmdFallback = join(localBin, "pi.cmd");
    addPowerShellPiCommand(join(HOME, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"), piExe, cmdFallback);
    addPowerShellPiCommand(join(HOME, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"), piExe, cmdFallback);
  }
}

writeFileSync(
  join(mainDir, "p", "remove-pi-documentation.js"),
  readFileSync(join(SRC_DIR, "lib", "remove-pi-documentation.js"), "utf8"),
);

rmSync(join(mainDir, "bin", "p"), { force: true });
rmSync(join(mainDir, "bin", "piwf"), { force: true });
if (WIN) {
  rmSync(join(mainDir, "bin", "p.cmd"), { force: true });
  rmSync(join(mainDir, "bin", "piwf.cmd"), { force: true });
}

if (existsSync(bunBinDir)) {
  for (const name of readdirSync(bunBinDir)) {
    const base = name.replace(/\.(cmd|ps1|exe|bat)$/i, "");
    if (base === "pi" || base === "agent-browser") {
      rmSync(join(bunBinDir, name), { force: true });
    }
  }
}

log("Writing Pi configuration");
writeConfig({
  mainPath: join(mainDir, "settings.json"),
  pPath: join(pDir, "settings.json"),
  wfPath: join(wfDir, "settings.json"),
  sttPath: join(mainDir, "stt.json"),
  npmPkgPath: join(npmDir, "package.json"),
  pNpmPkgPath: join(pDir, "npm", "package.json"),
  wfNpmPkgPath: join(wfDir, "npm", "package.json"),
  piVersion: versions.pi,
  keybindingsSrcPath: join(SRC_DIR, "config", "keybindings.json"),
  mainKeybindsPath: join(mainDir, "keybindings.json"),
  pKeybindsPath: join(pDir, "keybindings.json"),
  wfKeybindsPath: join(wfDir, "keybindings.json"),
  compactionSrcPath: join(SRC_DIR, "config", "compaction.json"),
  modelsStorePath: join(mainDir, "models-store.json"),
  modelTiersSrcPath: join(SRC_DIR, "config", "model-tiers.json"),
  modelTiersDestPath: join(HOME, ".pi", "workflows", "model-tiers.json"),
  shellPath: gitBash || undefined,
});

if (!WIN) {
  try {
    chmodSync(join(mainDir, "stt.json"), 0o600);
  } catch {
    /* ignore */
  }
}

run(bunBin, ["install", "--production", "--silent"], { cwd: npmDir, stdio: "ignore" });

sharePath(join(mainDir, "auth.json"), join(pDir, "auth.json"), false);
sharePath(join(mainDir, "models-store.json"), join(pDir, "models-store.json"), false);
sharePath(join(mainDir, "auth.json"), join(wfDir, "auth.json"), false);
sharePath(join(mainDir, "models-store.json"), join(wfDir, "models-store.json"), false);
rmSync(join(pDir, "bin"), { recursive: true, force: true });
sharePath(join(mainDir, "bin"), join(pDir, "bin"), true);
rmSync(join(wfDir, "bin"), { recursive: true, force: true });
rmSync(join(wfDir, "local"), { recursive: true, force: true });
rmSync(join(wfDir, "stt.json"), { force: true });
sharePath(join(mainDir, "bin"), join(wfDir, "bin"), true);
sharePath(join(mainDir, "local"), join(wfDir, "local"), true);

const zshrc = process.env.ZDOTDIR ? join(process.env.ZDOTDIR, ".zshrc") : join(HOME, ".zshrc");
addUnixPathLine(zshrc);
addUnixPathLine(join(HOME, ".bashrc"));
if (WIN) {
  addWindowsUserPath([localBin, bunBinDir]);
  addPowerShellPathLine(join(HOME, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"), [
    localBin,
    bunBinDir,
  ]);
  addPowerShellPathLine(join(HOME, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"), [
    localBin,
    bunBinDir,
  ]);
  setWindowsUserEnv("AGENT_BROWSER_HOME", agentBrowserRoot);
  process.env.AGENT_BROWSER_HOME = agentBrowserRoot;
}

if (process.env.PI_SETUP_SKIP_BROWSER_INSTALL === "1") {
  warn("Skipping Chrome installation because PI_SETUP_SKIP_BROWSER_INSTALL=1.");
} else {
  log("Installing browser runtime");
  const browser = WIN ? join(localBin, "agent-browser.cmd") : join(localBin, "agent-browser");
  const st = run(browser, ["install"]);
  if (st !== 0) {
    warn("Chrome download failed. Re-run 'agent-browser install' later; an existing compatible Chrome may still work.");
  }
}

if (!which("ffmpeg")) {
  warn(
    WIN
      ? "ffmpeg is not installed. Voice STT needs ffmpeg (winget install Gyan.FFmpeg) and microphone permission."
      : "ffmpeg is not installed. Voice STT needs ffmpeg and microphone permission.",
  );
}
if (!process.env.OPENAI_API_KEY) {
  warn("OPENAI_API_KEY is not set. Pi and Voice STT are configured for OpenAI but need that environment variable.");
}
if (WIN && !gitBash) {
  warn(
    "Git Bash was not found. Pi on Windows needs bash.exe (install Git for Windows). After installing it, re-run the installer so settings.json can set shellPath.",
  );
}

log("Verifying installation");
const piCmd = WIN ? join(localBin, "pi.cmd") : join(localBin, "pi");
const pCmd = WIN ? join(localBin, "p.cmd") : join(localBin, "p");
const piwfCmd = WIN ? join(localBin, "piwf.cmd") : join(localBin, "piwf");
const abCmd = WIN ? join(localBin, "agent-browser.cmd") : join(localBin, "agent-browser");
const verifyEnv = {
  ...process.env,
  PATH: `${localBin}${delimiter}${bunBinDir}${delimiter}${process.env.PATH || ""}`,
};
if (run(piCmd, ["--version"], { env: verifyEnv }) !== 0) fail("pi --version failed.");
if (run(pCmd, ["--version"], { env: verifyEnv }) !== 0) fail("p --version failed.");
if (run(piwfCmd, ["--version"], { env: verifyEnv }) !== 0) fail("piwf --version failed.");
if (run(abCmd, ["--version"], { env: verifyEnv }) !== 0) fail("agent-browser --version failed.");

const doctor = join(SRC_DIR, "bin", "pi-setup-doctor");
if (existsSync(doctor)) {
  if (WIN && !gitBash) {
    warn("pi-setup-doctor skipped (Git Bash not found).");
  } else {
    const doctorStatus = WIN
      ? run(gitBash, [doctor, "--quiet"], { env: verifyEnv })
      : run(doctor, ["--quiet"], { env: verifyEnv });
    if (doctorStatus !== 0) {
      warn("pi-setup-doctor reported problems; run 'bin/pi-setup-doctor' for detail.");
    }
  }
}

const voiceHint = WIN
  ? "Voice dictation: Alt+P. Newline: Ctrl+Enter, Shift+Enter, or Ctrl+J. Queue follow-up: Ctrl+Q."
  : "Voice dictation: Option+P (or the π it composes) on macOS, Alt+P on Linux.\nKeybindings:     newline Option+Enter / Ctrl+Enter / Ctrl+J, queue follow-up Ctrl+Q\n                 (or Option+Tab on macOS; Linux window managers grab Alt+Tab).\n                 See docs/KEYBINDINGS.md.";

console.log(`
Installed successfully.

Open a new terminal, then use:
  pi   Full setup minus dynamic workflows: Voice STT + browser + handoff briefs + monitor + /btw + MLX
  piwf Full setup with dynamic workflows (the historical pi): adds workflow + /workflows + workflow skills
  p    Lean setup: Voice STT + /btw + handoff briefs + MLX (macOS), quiet startup

${voiceHint}
Side questions:  /btw <question>, escape to return.

Extensions are installed from forks/ as Pi local packages. Run
'bin/pi-setup-doctor' to check that the installed copies still match this
repository and whether upstream has published newer versions.
`);
}

export {
  addPowerShellPiCommand,
  bunCandidates,
  findBun,
  findGitBash,
  install,
  installWindowsPiBinary,
  isUsableWindowsBash,
  posixPath,
  which,
  writeConfig,
  writeExec,
};

if (import.meta.main) install();
