import { readFile } from "node:fs/promises";
import type { SecretConfig } from "../config/types";
import { textFrom } from "../utils/coerce";
import { resolvePath } from "../utils/path";
import { formatError } from "../utils/text";
import { readKeychainSecret } from "./keychain";

const MAX_API_KEY_LENGTH = 4096;
const NON_KEY_CHARACTER = /[\s\p{Cc}]/u;

/**
 * apiKeyEnv/apiKeyFile can name any variable or file, and a file without an
 * `=` is read whole, so the value is checked to still look like a single
 * credential token before it can be sent as a Bearer header.
 */
const usableApiKey = (value: string, source: string): string => {
  if (!value) return "";
  if (value.length > MAX_API_KEY_LENGTH) {
    throw new Error(`API key from ${source} is too long (${value.length} characters, limit ${MAX_API_KEY_LENGTH}).`);
  }
  if (NON_KEY_CHARACTER.test(value)) {
    throw new Error(`API key from ${source} is not a single-line token; it must contain the key only.`);
  }
  return value;
};

const unquote = (value: string): string => {
  const trimmed = value.trim();
  if ((trimmed.startsWith("\"") && trimmed.endsWith("\"")) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
};

const parseApiKeyFile = (contents: string, envName: string): string => {
  const raw = contents.trim();
  if (!raw) return "";
  if (!raw.includes("=")) return raw;

  for (const line of raw.split(/\r?\n/)) {
    const withoutComment = line.trim();
    if (!withoutComment || withoutComment.startsWith("#")) continue;
    const normalized = withoutComment.startsWith("export ") ? withoutComment.slice("export ".length).trim() : withoutComment;
    const separator = normalized.indexOf("=");
    if (separator === -1) continue;
    const key = normalized.slice(0, separator).trim();
    if (key !== envName) continue;
    return unquote(normalized.slice(separator + 1));
  }

  return "";
};

const readApiKeyFile = async (filePath: string, envName: string): Promise<string> => {
  const resolved = resolvePath(filePath);
  try {
    return parseApiKeyFile(await readFile(resolved, "utf8"), envName);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") throw new Error(`API key file does not exist: ${resolved}`);
    throw new Error(`Cannot read API key file ${resolved}: ${formatError(error)}`);
  }
};

/**
 * Config that names no secret source at all — including an inline `apiKey`,
 * which is a named credential like any other and must still be sent. Loading
 * refuses a non-loopback endpoint that named none, so reaching run time in this
 * state means the endpoint was declared keyless on purpose (`apiKeyEnv: ""`):
 * it is called without an Authorization header rather than with a borrowed key.
 */
export const isDeclaredKeyless = (config: Pick<SecretConfig, "apiKey" | "apiKeyEnv" | "apiKeyFile" | "keychainService">): boolean =>
  !config.apiKey && !config.apiKeyEnv && !config.apiKeyFile && !config.keychainService;

export const resolveApiKey = async (input: Record<string, unknown>, defaultEnv: string): Promise<string> => {
  const explicitKey = textFrom(input.apiKey);
  if (explicitKey) return usableApiKey(explicitKey, "apiKey");

  const apiKeyEnv = typeof input.apiKeyEnv === "string" ? input.apiKeyEnv.trim() : defaultEnv;
  const envKey = apiKeyEnv ? textFrom(process.env[apiKeyEnv]) : "";
  if (envKey) return usableApiKey(envKey, `environment variable ${apiKeyEnv}`);

  const apiKeyFile = textFrom(input.apiKeyFile);
  const fileKey = apiKeyFile ? textFrom(await readApiKeyFile(apiKeyFile, apiKeyEnv)) : "";
  if (fileKey) return usableApiKey(fileKey, `file ${resolvePath(apiKeyFile)}`);

  const keychainKey = await readKeychainSecret(textFrom(input.keychainService), textFrom(input.keychainAccount));
  return usableApiKey(keychainKey, "the macOS Keychain");
};
