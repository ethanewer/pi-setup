import { spawn } from "node:child_process";
import { textFrom } from "../utils/coerce";
import { formatError, truncate } from "../utils/text";

/** `security` exit code for "the item is simply not in the Keychain". */
const ITEM_NOT_FOUND = 44;

const readStream = async (stream: NodeJS.ReadableStream | null): Promise<string> => {
  if (!stream) return "";
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
  }
  return Buffer.concat(chunks).toString("utf8");
};

export const readKeychainSecret = async (service: string, account: string): Promise<string> => {
  if (!service || process.platform !== "darwin") return "";

  const child = spawn("/usr/bin/security", [
    "find-generic-password",
    "-w",
    "-s",
    service,
    ...(account ? ["-a", account] : []),
  ], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  const [outcome, stdout, stderr] = await Promise.all([
    // spawn() reports ENOENT/EAGAIN through an 'error' event: without this
    // listener Node rethrows it and takes the whole host process down.
    new Promise<{ code: number | null; error?: unknown }>((resolve) => {
      child.once("error", (error) => resolve({ code: null, error }));
      child.once("close", (code) => resolve({ code }));
    }),
    readStream(child.stdout),
    readStream(child.stderr),
  ]);

  if (outcome.error) {
    throw new Error(`Cannot run /usr/bin/security to read the Keychain: ${formatError(outcome.error)}`);
  }
  if (outcome.code === 0) return textFrom(stdout);
  if (outcome.code === ITEM_NOT_FOUND) return "";

  const detail = truncate(stderr.trim()) || `exit ${outcome.code ?? "unknown"}`;
  throw new Error(`Keychain lookup failed for service "${service}"${account ? ` account "${account}"` : ""}: ${detail}`);
};
