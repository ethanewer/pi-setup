/**
 * Managed local MLX provider for pi.
 *
 * Commands:
 *   /mlx download [optimized-ornith]  Install the optimized Ornith-35B setup
 *   /mlx list                         List downloaded models and the served model
 *   /mlx load <model-id>              Load and serve a downloaded model
 *   /mlx stop                         Stop the extension-owned inference server
 *
 * Only the model successfully loaded by `/mlx load` is registered with pi and
 * shown in `/model` / `--list-models`. Downloaded-but-unserved models appear
 * only in `/mlx list`.
 *
 * Environment:
 *   MLX_API_URL       OpenAI base URL or server root (default 127.0.0.1:8080/v1)
 *   MLX_SERVER_BIN    Fallback mlx_lm.server executable path
 *   MLX_OPTIQ_BIN     OptiQ executable (preferred for supported text models)
 *   MLX_OPTIQ_PYTHON OptiQ Python interpreter (used by /mlx download)
 *   MLX_OMLX_BIN      oMLX executable (used for Ling and optimized Ornith-35B)
 *   MLX_ORNITH_MTP    Set to 1 to enable Ornith-35B MTP (off by default)
 *   MLX_HF_CACHE      Hugging Face hub cache root
 *   MLX_START_TIMEOUT Startup timeout in seconds (default 180)
 *   MLX_MODELS        Comma-separated extra model ids or local model paths
 */

import type { ExtensionAPI, ProviderModelConfig } from "@earendil-works/pi-coding-agent";
import type { ChildProcess } from "node:child_process";
import { spawn } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { connect } from "node:net";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";

const PROVIDER_ID = "mlx";
const PROVIDER_NAME = "MLX (Local)";
const DEFAULT_API_URL = "http://127.0.0.1:8080/v1";
const DEFAULT_CONTEXT_WINDOW = 32768;
const SERVING_CONTEXT_CAP = 131072;
const DEFAULT_MAX_TOKENS = 32768;
const MAX_LOG_CHARS = 12_000;

interface LocalModel {
  id: string;
  name: string;
  path?: string;
  modelType?: string;
  contextWindow: number;
  maxTokens: number;
}

interface ServePlan {
  command: string;
  args: string[];
  apiModelId: string;
  runtime: "OptiQ" | "oMLX" | "mlx-lm";
}

function normalizeApiUrl(value?: string): string {
  const url = new URL((value || DEFAULT_API_URL).trim());
  url.pathname = url.pathname.replace(/\/+$/, "");
  if (!url.pathname.endsWith("/v1")) url.pathname += "/v1";
  return url.toString().replace(/\/$/, "");
}

function resolveCacheDir(): string {
  const explicit = process.env.MLX_HF_CACHE ?? process.env.HF_HUB_CACHE;
  return explicit?.trim() || join(homedir(), ".cache", "huggingface", "hub");
}

function resolveServerBin(): string {
  const explicit = process.env.MLX_SERVER_BIN?.trim();
  if (explicit) return explicit;

  // Prefer uv/pipx-style isolated tools over user-site Python installs. This
  // prevents an older ~/Library/Python version from shadowing a current tool.
  const candidates = [join(homedir(), ".local", "bin", "mlx_lm.server")];
  const pythonRoot = join(homedir(), "Library", "Python");
  try {
    const versions = readdirSync(pythonRoot).sort((a, b) =>
      b.localeCompare(a, undefined, { numeric: true }),
    );
    candidates.push(
      ...versions.map((version) => join(pythonRoot, version, "bin", "mlx_lm.server")),
    );
  } catch {
    // Fall through to standard locations and PATH.
  }
  candidates.push(
    "/opt/homebrew/bin/mlx_lm.server",
    "/usr/local/bin/mlx_lm.server",
  );
  return candidates.find((candidate) => existsSync(candidate)) ?? "mlx_lm.server";
}

function resolveExecutable(environmentName: string, candidates: string[], fallback: string): string {
  const explicit = process.env[environmentName]?.trim();
  if (explicit) return explicit;
  return candidates.find((candidate) => existsSync(candidate)) ?? fallback;
}

function resolveOptiqBin(): string {
  return resolveExecutable(
    "MLX_OPTIQ_BIN",
    [join(homedir(), ".local", "bin", "optiq"), "/opt/homebrew/bin/optiq", "/usr/local/bin/optiq"],
    "optiq",
  );
}

function resolveOmlxBin(): string {
  return resolveExecutable(
    "MLX_OMLX_BIN",
    ["/opt/homebrew/bin/omlx", "/usr/local/bin/omlx", join(homedir(), ".omlx", "bin", "omlx")],
    "omlx",
  );
}

function resolveOptiqPython(): string {
  return resolveExecutable(
    "MLX_OPTIQ_PYTHON",
    [
      join(homedir(), ".local", "share", "uv", "tools", "mlx-optiq", "bin", "python"),
      join(homedir(), ".local", "share", "uv", "tools", "mlx-optiq", "bin", "python3"),
    ],
    "python3",
  );
}

function readJson(path: string): Record<string, any> | undefined {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
}

function contextWindowFromConfig(config: Record<string, any> | undefined): number {
  const candidates = [
    config?.max_position_embeddings,
    config?.model_max_length,
    config?.text_config?.max_position_embeddings,
  ];
  const value = candidates.find((v) => Number.isFinite(v) && v > 0);
  return typeof value === "number" ? value : DEFAULT_CONTEXT_WINDOW;
}

function looksLikeMlxModel(
  entry: string,
  snapshot: string,
  config: Record<string, any> | undefined,
): boolean {
  const hasConfig = existsSync(join(snapshot, "config.json"));
  const hasTokenizer =
    existsSync(join(snapshot, "tokenizer_config.json")) ||
    existsSync(join(snapshot, "tokenizer.json"));
  const hasWeights =
    existsSync(join(snapshot, "model.safetensors")) ||
    existsSync(join(snapshot, "model.safetensors.index.json"));
  const quant = config?.quantization ?? config?.quantization_config;
  const hasMlxQuantization =
    quant && Number.isFinite(quant.bits) && Number.isFinite(quant.group_size);
  const mlxNamed = entry.toLowerCase().includes("mlx");
  return hasConfig && hasTokenizer && hasWeights && (hasMlxQuantization || mlxNamed);
}

function discoverModels(): LocalModel[] {
  const cacheDir = resolveCacheDir();
  const found = new Map<string, LocalModel>();

  if (existsSync(cacheDir)) {
    for (const entry of readdirSync(cacheDir)) {
      if (!entry.startsWith("models--")) continue;

      const encoded = entry.slice("models--".length);
      const separator = encoded.indexOf("--");
      if (separator < 1) continue;
      const id = `${encoded.slice(0, separator)}/${encoded.slice(separator + 2)}`;
      const repoDir = join(cacheDir, entry);

      try {
        const refPath = join(repoDir, "refs", "main");
        if (!existsSync(refPath)) continue;
        const revision = readFileSync(refPath, "utf8").trim();
        if (!revision) continue;
        const snapshot = join(repoDir, "snapshots", revision);
        if (!statSync(snapshot).isDirectory()) continue;

        const config = readJson(join(snapshot, "config.json"));
        if (!looksLikeMlxModel(entry, snapshot, config)) continue;
        const contextWindow = contextWindowFromConfig(config);
        found.set(id, {
          id,
          name: id,
          path: snapshot,
          modelType: config?.model_type ?? config?.text_config?.model_type,
          contextWindow,
          maxTokens: Math.min(DEFAULT_MAX_TOKENS, contextWindow, SERVING_CONTEXT_CAP),
        });
      } catch {
        // Ignore incomplete/corrupt cache entries; loading them could not work.
      }
    }
  }

  for (const raw of (process.env.MLX_MODELS ?? "").split(",")) {
    const id = raw.trim();
    if (!id || found.has(id)) continue;
    let config: Record<string, any> | undefined;
    if (existsSync(id)) config = readJson(join(id, "config.json"));
    const contextWindow = contextWindowFromConfig(config);
    found.set(id, {
      id,
      name: existsSync(id) ? basename(id) : id,
      path: existsSync(id) ? realpathSync(id) : undefined,
      modelType: config?.model_type ?? config?.text_config?.model_type,
      contextWindow,
      maxTokens: Math.min(DEFAULT_MAX_TOKENS, contextWindow, SERVING_CONTEXT_CAP),
    });
  }

  return [...found.values()].sort((a, b) => a.id.localeCompare(b.id));
}

function servingContextForModel(model: LocalModel): number {
  // The 35B MoE weights fit resident, but a 131K prefill exhausts Metal
  // command-buffer memory on a 32 GB machine even with q4 KV. 65K is the
  // validated high-context profile for this model.
  if (model.id.includes("Ornith-1.5-35B-A3B")) return Math.min(model.contextWindow, 65536);
  // The 27B Qwen build passes a real 32K prefill with fused q4 KV, while 64K
  // still OOMs on this machine. Keep pi's compaction boundary at 32K.
  if (model.id.includes("Qwen3.8-27B")) return Math.min(model.contextWindow, 32768);
  return Math.min(model.contextWindow, SERVING_CONTEXT_CAP);
}

function toProviderModel(model: LocalModel): ProviderModelConfig {
  return {
    id: model.id,
    name: model.name,
    reasoning: false,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: servingContextForModel(model),
    maxTokens: model.maxTokens,
    compat: {
      maxTokensField: "max_tokens",
      supportsStore: false,
      supportsStrictMode: false,
      supportsDeveloperRole: false,
    },
  };
}

function executableAvailable(command: string): boolean {
  return !command.includes("/") || existsSync(command);
}

function makeServePlan(model: LocalModel, host: string, port: number): ServePlan {
  const source = model.path ?? model.id;
  const contextCap = servingContextForModel(model);

  const ornith35DonorOverlay = join(
    homedir(),
    ".local", "share", "mlx-models", "Ornith-1.5-35B-A3B-oQ4e-qwen36-mtp",
  );
  const useFastOrnith35 = [
    "ornith-ai/Ornith-1.5-35B-A3B-MLX-4bit",
    "mlx-works/Ornith-1.5-35B-A3B-oQ4e-mtp",
  ].includes(model.id) && existsSync(ornith35DonorOverlay);

  if (model.modelType === "bailing_hybrid" || useFastOrnith35) {
    const command = resolveOmlxBin();
    if (!executableAvailable(command)) {
      throw new Error(`oMLX was not found at ${command}. Install oMLX or set MLX_OMLX_BIN.`);
    }
    const servedSource = useFastOrnith35 ? ornith35DonorOverlay : model.path;
    if (!servedSource) throw new Error(`oMLX requires a downloaded local snapshot for ${model.id}.`);

    const modelDir = join(homedir(), ".pi", "mlx", "omlx-active");
    const basePath = join(homedir(), ".pi", "mlx", "omlx-data");
    const apiModelId = basename(model.id);
    rmSync(modelDir, { recursive: true, force: true });
    mkdirSync(modelDir, { recursive: true });
    mkdirSync(basePath, { recursive: true });
    symlinkSync(realpathSync(servedSource), join(modelDir, apiModelId), "dir");

    if (useFastOrnith35) {
      // The Qwen3.6 donor head is useful for deterministic long generations,
      // but a three-task agentic A/B measured a 2.6% token-weighted regression.
      // Keep it opt-in; TurboQuant q4 KV remains required for the 65K profile.
      const mtpEnabled = process.env.MLX_ORNITH_MTP === "1";
      writeFileSync(join(basePath, "model_settings.json"), JSON.stringify({
        version: 1,
        models: {
          [apiModelId]: {
            max_context_window: contextCap,
            turboquant_kv_enabled: true,
            turboquant_kv_bits: 4,
            turboquant_skip_last: true,
            dflash_enabled: false,
            mtp_enabled: mtpEnabled,
            mtp_num_draft_tokens: 2,
          },
        },
      }, null, 2));
    }

    return {
      command,
      apiModelId,
      runtime: "oMLX",
      args: [
        "serve",
        "--model-dir", modelDir,
        "--base-path", basePath,
        "--host", host,
        "--port", String(port),
        "--max-concurrent-requests", "1",
        "--memory-guard", useFastOrnith35 ? "off" : "aggressive",
        "--no-cache",
        "--no-hf-cache",
      ],
    };
  }

  const optiq = resolveOptiqBin();
  if (executableAvailable(optiq)) {
    return {
      command: optiq,
      apiModelId: model.id,
      runtime: "OptiQ",
      args: [
        "serve",
        "--model", source,
        "--host", host,
        "--port", String(port),
        "--kv-bits", "4",
        "--max-context", String(contextCap),
        "--max-concurrent", "1",
        "--no-auth",
        "--single-model",
      ],
    };
  }

  const command = resolveServerBin();
  if (!executableAvailable(command)) {
    throw new Error(`No MLX runtime was found. Set MLX_OPTIQ_BIN or MLX_SERVER_BIN.`);
  }
  return {
    command,
    apiModelId: model.id,
    runtime: "mlx-lm",
    args: ["--model", source, "--host", host, "--port", String(port)],
  };
}

function appendBounded(current: string, chunk: unknown): string {
  const next = current + String(chunk);
  return next.length > MAX_LOG_CHARS ? next.slice(-MAX_LOG_CHARS) : next;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function terminateProcess(process: ChildProcess): Promise<void> {
  if (process.exitCode !== null || process.signalCode !== null) return;
  process.kill("SIGTERM");
  await Promise.race([
    new Promise<void>((resolve) => process.once("exit", () => resolve())),
    delay(5_000),
  ]);
  if (process.exitCode !== null || process.signalCode !== null) return;
  process.kill("SIGKILL");
  await Promise.race([
    new Promise<void>((resolve) => process.once("exit", () => resolve())),
    delay(2_000),
  ]);
}

async function fetchWithTimeout(
  url: string,
  timeoutMs: number,
  init: RequestInit = {},
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function isPortOpen(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ host, port });
    const done = (open: boolean) => {
      socket.destroy();
      resolve(open);
    };
    socket.setTimeout(500);
    socket.once("connect", () => done(true));
    socket.once("timeout", () => done(false));
    socket.once("error", () => done(false));
  });
}

export default function mlxExtension(pi: ExtensionAPI) {
  // MLX and the managed runtimes are Apple-silicon/macOS specific. Loading the
  // extension on Linux is harmless but deliberately registers no commands or provider.
  if (process.platform !== "darwin") return;

  const apiUrl = normalizeApiUrl(process.env.MLX_API_URL ?? process.env.MLX_API_BASE);
  const parsedUrl = new URL(apiUrl);
  const host = parsedUrl.hostname === "localhost" ? "127.0.0.1" : parsedUrl.hostname;
  const port = Number(parsedUrl.port || (parsedUrl.protocol === "https:" ? 443 : 80));
  const healthUrl = `${parsedUrl.protocol}//${parsedUrl.host}/health`;
  const configuredTimeout = Number(process.env.MLX_START_TIMEOUT ?? "180");
  const startTimeoutMs = Number.isFinite(configuredTimeout)
    ? Math.max(10_000, configuredTimeout * 1000)
    : 180_000;

  let child: ChildProcess | undefined;
  let childModel: LocalModel | undefined;
  let childApiModelId: string | undefined;
  let childRuntime: ServePlan["runtime"] | undefined;
  let stderrTail = "";
  let stdoutTail = "";
  let stopping = false;

  const isHealthy = async (): Promise<boolean> => {
    try {
      const response = await fetchWithTimeout(healthUrl, 1_000);
      if (response.ok) return true;
    } catch {
      // Some runtimes expose only the OpenAI models endpoint.
    }
    try {
      const response = await fetchWithTimeout(`${apiUrl}/models`, 1_000);
      return response.ok;
    } catch {
      return false;
    }
  };

  const warmModel = async (apiModelId: string, timeoutMs: number): Promise<void> => {
    const response = await fetchWithTimeout(`${apiUrl}/chat/completions`, timeoutMs, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        model: apiModelId,
        messages: [{ role: "user", content: "Reply OK." }],
        max_tokens: 1,
        temperature: 0,
        stream: false,
      }),
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 2_000);
      throw new Error(`Model warm-up failed (${response.status})${detail ? `: ${detail}` : "."}`);
    }
  };

  const unregisterServedModel = () => {
    pi.unregisterProvider(PROVIDER_ID);
  };

  const registerServedModel = (model: LocalModel, apiModelId: string) => {
    pi.registerProvider(PROVIDER_ID, {
      name: PROVIDER_NAME,
      baseUrl: apiUrl,
      apiKey: "mlx-local",
      authHeader: false,
      api: "openai-completions",
      models: [toProviderModel({ ...model, id: apiModelId })],
    });
  };

  const stopOwnedServer = async (): Promise<boolean> => {
    const owned = child;
    if (!owned) {
      childModel = undefined;
      childApiModelId = undefined;
      childRuntime = undefined;
      unregisterServedModel();
      return false;
    }

    stopping = true;
    child = undefined;
    childModel = undefined;
    childApiModelId = undefined;
    childRuntime = undefined;
    unregisterServedModel();

    await terminateProcess(owned);
    stopping = false;
    return true;
  };

  const startServer = async (model: LocalModel): Promise<void> => {
    if (
      child &&
      childModel?.id === model.id &&
      childApiModelId &&
      child.exitCode === null &&
      (await isHealthy())
    ) {
      registerServedModel(model, childApiModelId);
      return;
    }

    await stopOwnedServer();

    if (parsedUrl.protocol !== "http:" || !["127.0.0.1", "::1"].includes(host)) {
      throw new Error(
        `Managed MLX requires a local http URL; got ${apiUrl}. ` +
          "Use MLX_API_URL=http://127.0.0.1:<port>/v1.",
      );
    }
    if (await isPortOpen(host, port)) {
      throw new Error(
        `Port ${host}:${port} is already occupied. The extension will not stop or reuse an unowned process.`,
      );
    }

    const plan = makeServePlan(model, host, port);
    stderrTail = "";
    stdoutTail = "";
    const owned = spawn(plan.command, plan.args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    });
    child = owned;
    childModel = model;
    childApiModelId = plan.apiModelId;
    childRuntime = plan.runtime;

    let spawnError: Error | undefined;
    owned.stdout?.on("data", (data) => {
      stdoutTail = appendBounded(stdoutTail, data);
    });
    owned.stderr?.on("data", (data) => {
      stderrTail = appendBounded(stderrTail, data);
    });
    owned.once("error", (error) => {
      spawnError = error;
    });
    owned.once("exit", () => {
      if (child === owned) {
        child = undefined;
        childModel = undefined;
        childApiModelId = undefined;
        childRuntime = undefined;
        unregisterServedModel();
      }
    });

    const deadline = Date.now() + startTimeoutMs;
    let startupFailure: Error | undefined;
    while (Date.now() < deadline) {
      if (spawnError) break;
      if (owned.exitCode !== null || owned.signalCode !== null) break;
      if (await isHealthy()) {
        try {
          if (child !== owned) throw new Error("MLX startup was cancelled.");
          await warmModel(plan.apiModelId, Math.max(1_000, deadline - Date.now()));
          if (child !== owned) throw new Error("MLX startup was cancelled.");
          registerServedModel(model, plan.apiModelId);
          return;
        } catch (error) {
          startupFailure = error instanceof Error ? error : new Error(String(error));
          break;
        }
      }
      await delay(500);
    }

    const detail = (stderrTail || stdoutTail).trim();
    if (child === owned) {
      child = undefined;
      childModel = undefined;
      childApiModelId = undefined;
      childRuntime = undefined;
    }
    await terminateProcess(owned);
    unregisterServedModel();

    if (spawnError) throw new Error(`Failed to start ${plan.runtime}: ${spawnError.message}`);
    if (startupFailure) {
      throw new Error(
        `${plan.runtime} could not load ${model.id}: ${startupFailure.message}` +
          `${detail ? `\n${detail}` : ""}`,
      );
    }
    if (owned.exitCode !== null || owned.signalCode !== null) {
      throw new Error(
        `${plan.runtime} exited before becoming ready${detail ? `:\n${detail}` : "."}`,
      );
    }
    throw new Error(
      `Timed out after ${Math.round(startTimeoutMs / 1000)}s loading ${model.id} with ${plan.runtime}` +
        `${detail ? `:\n${detail}` : "."}`,
    );
  };

  // A fresh pi process starts with no extension-owned server, so no MLX models
  // belong in /model until `/mlx load` succeeds.
  unregisterServedModel();

  pi.registerCommand("mlx", {
    description: "Manage local MLX models: download, load, stop, or list",
    getArgumentCompletions: (prefix) => {
      const value = prefix.trimStart();
      if (!value.includes(" ")) {
        const commands = ["load", "stop", "list", "download"];
        const matches = commands.filter((command) => command.startsWith(value));
        return matches.length ? matches.map((command) => ({ value: command, label: command })) : null;
      }
      const [command, ...parts] = value.split(/\s+/);
      if (command === "download") {
        const target = "optimized-ornith";
        return target.startsWith(parts.join(" ")) ? [{ value: `download ${target}`, label: target }] : null;
      }
      if (command !== "load") return null;
      const modelPrefix = parts.join(" ");
      const matches = discoverModels().filter((model) => model.id.startsWith(modelPrefix));
      return matches.length
        ? matches.map((model) => ({ value: `load ${model.id}`, label: model.id }))
        : null;
    },
    handler: async (args, ctx) => {
      const trimmed = args.trim();
      const firstSpace = trimmed.indexOf(" ");
      const command = (firstSpace === -1 ? trimmed : trimmed.slice(0, firstSpace)).toLowerCase();
      let requested = firstSpace === -1 ? "" : trimmed.slice(firstSpace + 1).trim();

      if (command === "download") {
        await ctx.waitForIdle();
        const target = requested.toLowerCase();
        if (target && !["ornith", "optimized-ornith", "ornith-35b"].includes(target)) {
          ctx.ui.notify("Usage: /mlx download [optimized-ornith]", "warning");
          return;
        }
        if (child && child.exitCode === null) {
          ctx.ui.notify("Stop the served MLX model before downloading: /mlx stop", "error");
          return;
        }

        const python = resolveOptiqPython();
        if (!executableAvailable(python)) {
          ctx.ui.notify(
            `OptiQ's Python runtime was not found at ${python}. Install mlx-optiq or set MLX_OPTIQ_PYTHON.`,
            "error",
          );
          return;
        }
        const script = fileURLToPath(new URL("./build_ornith.py", import.meta.url));
        if (!existsSync(script)) {
          ctx.ui.notify(`Optimized Ornith installer is missing: ${script}`, "error");
          return;
        }

        ctx.ui.setStatus("mlx-download", "downloading optimized Ornith-35B…");
        ctx.ui.notify(
          "Downloading the calibrated Ornith-35B trunk and Qwen3.6 donor MTP head. " +
            "This may download about 21 GB and temporarily require additional disk space.",
          "info",
        );
        try {
          const result = await pi.exec(python, [script], { timeout: 2 * 60 * 60 * 1000 });
          const output = `${result.stdout}\n${result.stderr}`.trim();
          if (result.code !== 0) {
            throw new Error(output.slice(-4_000) || `installer exited with code ${result.code}`);
          }
          ctx.ui.notify(output.slice(-4_000) || "Optimized Ornith-35B setup is ready.", "info");
        } catch (error) {
          ctx.ui.notify(
            `Optimized Ornith download failed: ${error instanceof Error ? error.message : String(error)}`,
            "error",
          );
        } finally {
          ctx.ui.setStatus("mlx-download", undefined);
        }
        return;
      }

      if (command === "list") {
        const models = discoverModels();
        const live = child && child.exitCode === null && (await isHealthy()) ? childModel : undefined;
        if (!models.length) {
          ctx.ui.notify(`No downloaded MLX models found in ${resolveCacheDir()}.`, "warning");
          return;
        }
        const lines = models.map(
          (model) => `${live?.id === model.id ? "● served" : "○ downloaded"}  ${model.id}`,
        );
        ctx.ui.notify(lines.join("\n"), "info");
        return;
      }

      if (command === "stop") {
        await ctx.waitForIdle();
        if (ctx.model?.provider === PROVIDER_ID) {
          const fallback = ctx.modelRegistry
            .getAvailable()
            .find((model) => model.provider !== PROVIDER_ID);
          if (fallback) await pi.setModel(fallback);
        }
        const stopped = await stopOwnedServer();
        ctx.ui.notify(stopped ? "MLX server stopped." : "No extension-owned MLX server is running.", "info");
        return;
      }

      if (command === "load") {
        await ctx.waitForIdle();
        const models = discoverModels();
        if (!models.length) {
          ctx.ui.notify(`No downloaded MLX models found in ${resolveCacheDir()}.`, "error");
          return;
        }
        if (!requested && ctx.hasUI) {
          requested = (await ctx.ui.select(
            "Load and serve an MLX model",
            models.map((model) => model.id),
          )) ?? "";
        }
        if (!requested) {
          ctx.ui.notify("Usage: /mlx load <model-id>", "warning");
          return;
        }
        const exact = models.find((model) => model.id === requested);
        const suffixMatches = models.filter(
          (model) => model.id.toLowerCase().endsWith(`/${requested.toLowerCase()}`),
        );
        const model = exact ?? (suffixMatches.length === 1 ? suffixMatches[0] : undefined);
        if (!model) {
          ctx.ui.notify(`Downloaded MLX model not found: ${requested}. Run /mlx list.`, "error");
          return;
        }

        ctx.ui.notify(`Loading and warming ${model.id}…`, "info");
        try {
          await startServer(model);
          const registered = childApiModelId
            ? ctx.modelRegistry.find(PROVIDER_ID, childApiModelId)
            : undefined;
          const selected = registered ? await pi.setModel(registered) : false;
          ctx.ui.notify(
            `${childRuntime ?? "MLX"} is serving ${model.id}.` +
              `${selected ? " It is now selected." : " Select it in /model."}`,
            "info",
          );
        } catch (error) {
          if (ctx.model?.provider === PROVIDER_ID) {
            const fallback = ctx.modelRegistry
              .getAvailable()
              .find((available) => available.provider !== PROVIDER_ID);
            if (fallback) await pi.setModel(fallback);
          }
          ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
        }
        return;
      }

      ctx.ui.notify(
        "Usage: /mlx download [optimized-ornith] | /mlx load <model-id> | /mlx stop | /mlx list",
        "info",
      );
    },
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    if (ctx.model?.provider !== PROVIDER_ID) return;
    if (
      !child ||
      child.exitCode !== null ||
      childApiModelId !== ctx.model.id ||
      !childModel ||
      !(await isHealthy())
    ) {
      throw new Error(
        `MLX model ${ctx.model.id} is not being served. Run /mlx load ${childModel?.id ?? ctx.model.id}.`,
      );
    }
  });

  // mlx-lm 0.29 may emit null tool-call ids and finish_reason="stop" for a
  // tool response. Normalize the finalized message before pi executes tools.
  let toolMessageSequence = 0;
  pi.on("message_end", (event) => {
    const message = event.message;
    if (message.role !== "assistant" || message.provider !== PROVIDER_ID) return;
    const toolCalls = message.content.filter((block) => block.type === "toolCall");
    if (!toolCalls.length) return;
    const sequence = ++toolMessageSequence;
    return {
      message: {
        ...message,
        stopReason: "toolUse" as const,
        content: message.content.map((block, index) =>
          block.type === "toolCall" && !block.id
            ? { ...block, id: `mlx_call_${sequence}_${index}` }
            : block,
        ),
      },
    };
  });

  pi.on("session_shutdown", async () => {
    if (!stopping) await stopOwnedServer();
  });
}
