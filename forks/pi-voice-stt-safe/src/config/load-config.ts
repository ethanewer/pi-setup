import { readFile } from "node:fs/promises";
import {
  defaultAssemblyAiProviderConfig,
  defaultBridgeCaptureConfig,
  defaultCaptureConfig,
  defaultCleanupConfig,
  defaultDeepgramProviderConfig,
  defaultFfmpegCaptureConfig,
  defaultElevenLabsProviderConfig,
  defaultGladiaProviderConfig,
  defaultMistralProviderConfig,
  defaultOpenAiCompatibleProviderConfig,
  defaultOutputConfig,
  defaultVoiceCommandsConfig,
} from "./defaults";
import { isLoopbackEndpoint, isVendorEndpoint, secureEndpointFrom } from "./endpoint";
import type {
  AssemblyAiProviderConfig,
  BridgeCaptureConfig,
  CaptureConfig,
  CleanupConfig,
  DeepgramProviderConfig,
  FfmpegCaptureConfig,
  ElevenLabsProviderConfig,
  GladiaProviderConfig,
  MistralProviderConfig,
  OpenAiCompatibleProviderConfig,
  PluginConfig,
  ProviderConfig,
  VoiceCommandsConfig,
} from "./types";
import { resolveApiKey } from "../secrets/resolve-api-key";
import { booleanFrom, objectFrom, positiveIntegerFrom, stringArrayFrom, stringMapFrom, textFrom } from "../utils/coerce";
import { resolveExecutablePath } from "../utils/executable";
import { resolvePath } from "../utils/path";
import { deepMerge } from "../utils/merge";
import { modeOverrideFrom } from "../core/modes";
import { formatError } from "../utils/text";

export const readConfigFile = async (filePath: string): Promise<Record<string, unknown>> => {
  if (!filePath) return {};
  const resolved = resolvePath(filePath);
  try {
    return objectFrom(JSON.parse(await readFile(resolved, "utf8")));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") throw new Error(`STT config file does not exist: ${resolved}`);
    throw new Error(`Cannot parse STT config ${resolved}: ${formatError(error)}`);
  }
};

const mergedInput = async (options: Record<string, unknown>): Promise<Record<string, unknown>> => {
  const fileConfig = await readConfigFile(textFrom(options.configPath));
  const modeName = textFrom(options.mode, textFrom(fileConfig.mode, "default"));
  const merged = { ...options, ...fileConfig };
  return deepMerge(merged, modeOverrideFrom(fileConfig, modeName));
};

const readTextFile = async (filePath: string, label: string): Promise<string> => {
  const resolved = resolvePath(filePath);
  try {
    return await readFile(resolved, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") throw new Error(`${label} does not exist: ${resolved}`);
    throw new Error(`Cannot read ${label} ${resolved}: ${formatError(error)}`);
  }
};

const envNameFrom = (value: unknown, fallback: string): string => {
  if (typeof value === "string") return value.trim();
  return fallback;
};

/**
 * Both accepted values return a JSON body with a `text` field, which is what
 * the provider parses; anything else is refused instead of silently ignored.
 */
const responseFormatFrom = (
  value: unknown,
  fallback: OpenAiCompatibleProviderConfig["responseFormat"],
): OpenAiCompatibleProviderConfig["responseFormat"] => {
  const format = textFrom(value, fallback).toLowerCase();
  if (format === "json" || format === "verbose_json") return format;
  throw new Error(`Unsupported STT provider.responseFormat: ${format}. Use "json" or "verbose_json".`);
};

const commonCaptureFields = (
  capture: Record<string, unknown>,
  merged: Record<string, unknown>,
  defaults: { maxSeconds: number; minBytes: number },
) => ({
  maxSeconds: positiveIntegerFrom(capture.maxSeconds ?? merged.maxSeconds, defaults.maxSeconds),
  minBytes: Math.max(44, positiveIntegerFrom(capture.minBytes ?? merged.minBytes, defaults.minBytes)),
});

/**
 * A missing ffmpeg is a run-time problem, not a config syntax error: the
 * failure is reported so `/stt status` and `/stt doctor` still load, and the
 * recorder refuses to spawn anything until capture.ffmpegPath resolves.
 */
const ffmpegPathFrom = async (command: string): Promise<Pick<FfmpegCaptureConfig, "ffmpegPath" | "ffmpegPathError">> => {
  try {
    return { ffmpegPath: await resolveExecutablePath(command, "STT capture.ffmpegPath"), ffmpegPathError: "" };
  } catch (error) {
    return { ffmpegPath: command, ffmpegPathError: formatError(error) };
  }
};

const ffmpegCaptureFrom = async (merged: Record<string, unknown>, capture: Record<string, unknown>): Promise<FfmpegCaptureConfig> => ({
  type: "ffmpeg",
  ...(await ffmpegPathFrom(textFrom(capture.ffmpegPath, textFrom(capture.ffmpeg, textFrom(merged.ffmpeg, defaultFfmpegCaptureConfig.ffmpegPath))))),
  inputFormat: textFrom(capture.inputFormat, textFrom(merged.inputFormat, defaultFfmpegCaptureConfig.inputFormat)),
  input: textFrom(capture.input, textFrom(merged.input, defaultFfmpegCaptureConfig.input)),
  sampleRate: positiveIntegerFrom(capture.sampleRate ?? merged.sampleRate, defaultFfmpegCaptureConfig.sampleRate),
  channels: positiveIntegerFrom(capture.channels ?? merged.channels, defaultFfmpegCaptureConfig.channels),
  ...commonCaptureFields(capture, merged, defaultFfmpegCaptureConfig),
});

const bridgeCaptureFrom = async (merged: Record<string, unknown>, capture: Record<string, unknown>): Promise<BridgeCaptureConfig> => {
  const tokenEnv = envNameFrom(capture.tokenEnv ?? merged.bridgeTokenEnv, defaultBridgeCaptureConfig.tokenEnv);
  const tokenFile = textFrom(capture.tokenFile, textFrom(merged.bridgeTokenFile, defaultBridgeCaptureConfig.tokenFile));
  const explicitToken = textFrom(capture.token, textFrom(merged.bridgeToken));
  const envToken = tokenEnv ? textFrom(process.env[tokenEnv]) : "";
  const fileToken = !explicitToken && !envToken && tokenFile ? textFrom(await readTextFile(tokenFile, "STT bridge token file")) : "";

  return {
    type: "bridge",
    endpoint: secureEndpointFrom(capture.endpoint ?? merged.bridgeEndpoint, defaultBridgeCaptureConfig.endpoint),
    token: explicitToken || envToken || fileToken,
    tokenEnv,
    tokenFile,
    requestTimeoutSeconds: positiveIntegerFrom(
      capture.requestTimeoutSeconds ?? merged.bridgeRequestTimeoutSeconds,
      defaultBridgeCaptureConfig.requestTimeoutSeconds,
    ),
    ...commonCaptureFields(capture, merged, defaultBridgeCaptureConfig),
  };
};

const captureFrom = async (merged: Record<string, unknown>): Promise<CaptureConfig> => {
  const capture = objectFrom(merged.capture);
  const captureType = textFrom(capture.type, textFrom(merged.capture, defaultFfmpegCaptureConfig.type)).toLowerCase();

  if (captureType === "ffmpeg") return ffmpegCaptureFrom(merged, capture);
  if (captureType === "bridge") return bridgeCaptureFrom(merged, capture);

  throw new Error(`Unsupported STT capture type: ${captureType}`);
};

const secretSourceFrom = (merged: Record<string, unknown>, provider: Record<string, unknown>): Record<string, unknown> => ({
  apiKey: provider.apiKey ?? merged.apiKey,
  apiKeyEnv: provider.apiKeyEnv ?? merged.apiKeyEnv,
  apiKeyFile: provider.apiKeyFile ?? merged.apiKeyFile,
  keychainService: provider.keychainService ?? merged.keychainService,
  keychainAccount: provider.keychainAccount ?? merged.keychainAccount,
});

/**
 * An explicit apiKeyEnv counts even when empty: `"apiKeyEnv": ""` is how a
 * config says "this endpoint is deliberately keyless".
 */
const namesSecretExplicitly = (secrets: Record<string, unknown>): boolean =>
  typeof secrets.apiKeyEnv === "string" ||
  Boolean(textFrom(secrets.apiKey) || textFrom(secrets.apiKeyFile) || textFrom(secrets.keychainService));

/**
 * `openai-compatible`, `local` and cleanup.endpoint accept arbitrary hosts, so
 * the defaulted OpenAI credential may only follow an OpenAI host: any other
 * host has to name the secret it is allowed to receive, which keeps a
 * redirected endpoint from inheriting OPENAI_API_KEY along with the audio.
 * A loopback endpoint needs no credential of its own and gets no default, on
 * http and https alike — an https local server still loads without one.
 */
const openAiKeyEnvDefault = (endpoint: string, secrets: Record<string, unknown>, defaultEnv: string, label: string): string => {
  if (!defaultEnv || isVendorEndpoint(endpoint, "openai")) return defaultEnv;
  if (namesSecretExplicitly(secrets) || isLoopbackEndpoint(endpoint)) return "";

  throw new Error(
    `STT ${label}.endpoint ${new URL(endpoint).hostname} is not an OpenAI host, so it needs its own credential: ` +
      `set ${label}.apiKeyEnv (or ${label}.apiKey, ${label}.apiKeyFile, ${label}.keychainService), ` +
      `or ${label}.apiKeyEnv "" for an endpoint that takes no key. ` +
      `The ${defaultEnv} default applies to OpenAI endpoints only.`,
  );
};

/**
 * `local` names a server on this machine and defaults to no credential at all,
 * so its endpoint pointing somewhere else is surprising enough to have to be
 * meant: the config declares which credential that host receives, or
 * `apiKeyEnv: ""` to keep sending it audio with none. Without that opt-in the
 * type and the endpoint disagree, and the audio leaves the machine anyway.
 */
const assertLocalProviderStaysLocal = (endpoint: string, secrets: Record<string, unknown>): void => {
  if (isLoopbackEndpoint(endpoint) || namesSecretExplicitly(secrets)) return;

  throw new Error(
    `STT provider.type "local" points at ${new URL(endpoint).hostname}, which is not this machine, so the remote host has to be deliberate: ` +
      `set provider.apiKeyEnv (or provider.apiKey, provider.apiKeyFile, provider.keychainService) to name the credential it receives, ` +
      `or provider.apiKeyEnv "" to send it audio with no credential on purpose. ` +
      `provider.type "openai-compatible" is the type for a remote OpenAI-compatible server.`,
  );
};

const commonProviderFields = async <TDefault extends { apiKeyEnv: string; timeoutSeconds: number }>(
  merged: Record<string, unknown>,
  provider: Record<string, unknown>,
  defaults: TDefault,
) => {
  const secrets = secretSourceFrom(merged, provider);
  return {
    timeoutSeconds: positiveIntegerFrom(provider.timeoutSeconds ?? merged.requestTimeoutSeconds, defaults.timeoutSeconds),
    apiKey: await resolveApiKey(secrets, defaults.apiKeyEnv),
    apiKeyEnv: envNameFrom(secrets.apiKeyEnv, defaults.apiKeyEnv),
    apiKeyFile: textFrom(secrets.apiKeyFile),
    keychainService: textFrom(secrets.keychainService),
    keychainAccount: textFrom(secrets.keychainAccount),
  };
};

const mistralProviderFrom = async (merged: Record<string, unknown>, provider: Record<string, unknown>): Promise<MistralProviderConfig> => ({
  type: "mistral",
  endpoint: secureEndpointFrom(provider.endpoint ?? merged.endpoint, defaultMistralProviderConfig.endpoint, "mistral"),
  model: textFrom(provider.model, textFrom(merged.model, defaultMistralProviderConfig.model)),
  language: textFrom(provider.language, textFrom(merged.language, defaultMistralProviderConfig.language)),
  ...(await commonProviderFields(merged, provider, defaultMistralProviderConfig)),
});

const openAiCompatibleProviderFrom = async (
  merged: Record<string, unknown>,
  provider: Record<string, unknown>,
  vendor = "",
): Promise<OpenAiCompatibleProviderConfig> => {
  // A provider.endpoint that is present but unusable (`""`, blank, not a
  // string) means "this type's default", so it falls back to the endpoint the
  // type already put in `merged` rather than to OpenAI's: a blank endpoint must
  // not retarget `local` or `groq` at api.openai.com behind the checks below.
  const endpoint = secureEndpointFrom(
    provider.endpoint ?? merged.endpoint,
    textFrom(merged.endpoint, defaultOpenAiCompatibleProviderConfig.endpoint),
    vendor,
  );
  // A named vendor is already pinned to its own domain; an unpinned host only
  // gets a credential it named itself (or the OpenAI default on OpenAI hosts).
  const defaults = vendor
    ? defaultOpenAiCompatibleProviderConfig
    : {
        ...defaultOpenAiCompatibleProviderConfig,
        apiKeyEnv: openAiKeyEnvDefault(
          endpoint,
          secretSourceFrom(merged, provider),
          defaultOpenAiCompatibleProviderConfig.apiKeyEnv,
          "provider",
        ),
      };

  return {
    type: "openai-compatible",
    endpoint,
    model: textFrom(provider.model, textFrom(merged.model, defaultOpenAiCompatibleProviderConfig.model)),
    language: textFrom(provider.language, textFrom(merged.language, defaultOpenAiCompatibleProviderConfig.language)),
    responseFormat: responseFormatFrom(provider.responseFormat ?? merged.responseFormat, defaultOpenAiCompatibleProviderConfig.responseFormat),
    ...(await commonProviderFields(merged, provider, defaults)),
  };
};

const deepgramProviderFrom = async (merged: Record<string, unknown>, provider: Record<string, unknown>): Promise<DeepgramProviderConfig> => ({
  type: "deepgram",
  endpoint: secureEndpointFrom(provider.endpoint ?? merged.endpoint, defaultDeepgramProviderConfig.endpoint, "deepgram"),
  model: textFrom(provider.model, textFrom(merged.model, defaultDeepgramProviderConfig.model)),
  language: textFrom(provider.language, textFrom(merged.language, defaultDeepgramProviderConfig.language)),
  smartFormat: booleanFrom(provider.smartFormat ?? merged.smartFormat, defaultDeepgramProviderConfig.smartFormat),
  ...(await commonProviderFields(merged, provider, defaultDeepgramProviderConfig)),
});

const elevenLabsProviderFrom = async (
  merged: Record<string, unknown>,
  provider: Record<string, unknown>,
): Promise<ElevenLabsProviderConfig> => ({
  type: "elevenlabs",
  endpoint: secureEndpointFrom(provider.endpoint ?? merged.endpoint, defaultElevenLabsProviderConfig.endpoint, "elevenlabs"),
  model: textFrom(provider.model, textFrom(merged.model, defaultElevenLabsProviderConfig.model)),
  language: textFrom(provider.language, textFrom(merged.language, defaultElevenLabsProviderConfig.language)),
  ...(await commonProviderFields(merged, provider, defaultElevenLabsProviderConfig)),
});

const gladiaProviderFrom = async (merged: Record<string, unknown>, provider: Record<string, unknown>): Promise<GladiaProviderConfig> => ({
  type: "gladia",
  uploadEndpoint: secureEndpointFrom(provider.uploadEndpoint ?? provider.upload_endpoint ?? merged.uploadEndpoint, defaultGladiaProviderConfig.uploadEndpoint, "gladia"),
  transcriptionEndpoint: secureEndpointFrom(
    provider.transcriptionEndpoint ?? provider.transcription_endpoint ?? merged.transcriptionEndpoint,
    defaultGladiaProviderConfig.transcriptionEndpoint,
    "gladia",
  ),
  model: textFrom(provider.model, textFrom(merged.model, defaultGladiaProviderConfig.model)),
  language: textFrom(provider.language, textFrom(merged.language, defaultGladiaProviderConfig.language)),
  pollIntervalMs: positiveIntegerFrom(provider.pollIntervalMs ?? merged.pollIntervalMs, defaultGladiaProviderConfig.pollIntervalMs),
  ...(await commonProviderFields(merged, provider, defaultGladiaProviderConfig)),
});

const assemblyAiProviderFrom = async (
  merged: Record<string, unknown>,
  provider: Record<string, unknown>,
): Promise<AssemblyAiProviderConfig> => ({
  type: "assemblyai",
  uploadEndpoint: secureEndpointFrom(provider.uploadEndpoint ?? provider.upload_endpoint ?? merged.uploadEndpoint, defaultAssemblyAiProviderConfig.uploadEndpoint, "assemblyai"),
  transcriptEndpoint: secureEndpointFrom(
    provider.transcriptEndpoint ?? provider.transcript_endpoint ?? merged.transcriptEndpoint,
    defaultAssemblyAiProviderConfig.transcriptEndpoint,
    "assemblyai",
  ),
  model: textFrom(provider.model, textFrom(merged.model, defaultAssemblyAiProviderConfig.model)),
  language: textFrom(provider.language, textFrom(merged.language, defaultAssemblyAiProviderConfig.language)),
  pollIntervalMs: positiveIntegerFrom(provider.pollIntervalMs ?? merged.pollIntervalMs, defaultAssemblyAiProviderConfig.pollIntervalMs),
  ...(await commonProviderFields(merged, provider, defaultAssemblyAiProviderConfig)),
});

/**
 * `local` is `openai-compatible` aimed at this machine, and its `apiKeyEnv: ""`
 * is an implicit "this server takes no key" — which is why the endpoint is
 * checked against what the config itself named, before this is merged in.
 */
const localProviderDefaults = { endpoint: "http://localhost:10301/v1/audio/transcriptions", model: "whisper-1", apiKeyEnv: "" };

const providerFrom = async (merged: Record<string, unknown>): Promise<ProviderConfig> => {
  const provider = objectFrom(merged.provider);
  const providerType = textFrom(provider.type, textFrom(merged.provider, defaultMistralProviderConfig.type)).toLowerCase();

  if (providerType === "mistral" || providerType === "voxtral") return mistralProviderFrom(merged, provider);

  if (providerType === "openai-compatible" || providerType === "openai" || providerType === "groq" || providerType === "local") {
    const providerDefaults = providerType === "groq"
      ? { endpoint: "https://api.groq.com/openai/v1/audio/transcriptions", model: "whisper-large-v3-turbo", apiKeyEnv: "GROQ_API_KEY" }
      : providerType === "local"
        ? localProviderDefaults
        : providerType === "openai"
          ? { endpoint: "https://api.openai.com/v1/audio/transcriptions", model: "gpt-4o-mini-transcribe", apiKeyEnv: "OPENAI_API_KEY" }
          : {};
    const vendor = providerType === "openai" || providerType === "groq" ? providerType : "";
    // The type defaults win over a top-level `endpoint`, so the endpoint judged
    // here is the one the provider is actually built with, and the secrets are
    // read before `apiKeyEnv: ""` is merged in as the type's own default.
    if (providerType === "local") {
      assertLocalProviderStaysLocal(
        secureEndpointFrom(provider.endpoint, localProviderDefaults.endpoint),
        secretSourceFrom(merged, provider),
      );
    }
    return openAiCompatibleProviderFrom({ ...merged, ...providerDefaults }, provider, vendor);
  }

  if (providerType === "deepgram") return deepgramProviderFrom(merged, provider);
  if (providerType === "elevenlabs" || providerType === "eleven-labs" || providerType === "scribe") return elevenLabsProviderFrom(merged, provider);
  if (providerType === "gladia" || providerType === "gradium") return gladiaProviderFrom(merged, provider);
  if (providerType === "assemblyai" || providerType === "assembly-ai") return assemblyAiProviderFrom(merged, provider);

  throw new Error(`Unsupported STT provider: ${providerType}`);
};

const outputFrom = (merged: Record<string, unknown>) => {
  const output = objectFrom(merged.output);
  return {
    appendTrailingSpace: booleanFrom(output.appendTrailingSpace ?? merged.appendTrailingSpace, defaultOutputConfig.appendTrailingSpace),
    replacements: stringMapFrom(output.replacements ?? merged.replacements, defaultOutputConfig.replacements),
  };
};

const cleanupFrom = async (merged: Record<string, unknown>): Promise<CleanupConfig> => {
  const cleanup = objectFrom(merged.cleanup);
  const enabled = booleanFrom(cleanup.enabled, defaultCleanupConfig.enabled);
  const endpoint = secureEndpointFrom(cleanup.endpoint, defaultCleanupConfig.endpoint);
  // cleanup.endpoint is the generic OpenAI-compatible chat escape hatch, so the
  // OPENAI_API_KEY default may only follow it to OpenAI's own hosts. A disabled
  // cleanup is never called, so it is not worth refusing to load over.
  const apiKeyEnvDefault = enabled
    ? openAiKeyEnvDefault(endpoint, cleanup, defaultCleanupConfig.apiKeyEnv, "cleanup")
    : isVendorEndpoint(endpoint, "openai")
      ? defaultCleanupConfig.apiKeyEnv
      : "";

  return {
    enabled,
    endpoint,
    model: textFrom(cleanup.model, defaultCleanupConfig.model),
    language: textFrom(cleanup.language, defaultCleanupConfig.language),
    prompt: textFrom(cleanup.prompt, defaultCleanupConfig.prompt),
    projectTerms: stringArrayFrom(cleanup.projectTerms, defaultCleanupConfig.projectTerms),
    useRepoContext: booleanFrom(cleanup.useRepoContext, defaultCleanupConfig.useRepoContext),
    maxTokens: positiveIntegerFrom(cleanup.maxTokens, defaultCleanupConfig.maxTokens),
    timeoutSeconds: positiveIntegerFrom(cleanup.timeoutSeconds, defaultCleanupConfig.timeoutSeconds),
    apiKey: await resolveApiKey(cleanup, apiKeyEnvDefault),
    apiKeyEnv: envNameFrom(cleanup.apiKeyEnv, apiKeyEnvDefault),
    apiKeyFile: textFrom(cleanup.apiKeyFile),
    keychainService: textFrom(cleanup.keychainService),
    keychainAccount: textFrom(cleanup.keychainAccount),
  };
};

const commandsFrom = (merged: Record<string, unknown>): VoiceCommandsConfig => {
  const commands = objectFrom(merged.commands);
  return {
    enabled: booleanFrom(commands.enabled, defaultVoiceCommandsConfig.enabled),
    send: stringArrayFrom(commands.send, defaultVoiceCommandsConfig.send),
    clear: stringArrayFrom(commands.clear, defaultVoiceCommandsConfig.clear),
    newline: stringArrayFrom(commands.newline, defaultVoiceCommandsConfig.newline),
  };
};

export const loadConfig = async (options: Record<string, unknown> = {}): Promise<PluginConfig> => {
  const merged = await mergedInput(options);
  return {
    capture: await captureFrom(merged),
    provider: await providerFrom(merged),
    output: outputFrom(merged),
    cleanup: await cleanupFrom(merged),
    commands: commandsFrom(merged),
  };
};
