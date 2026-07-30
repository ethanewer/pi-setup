import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { objectFrom, textFrom } from "../utils/coerce";
import { DEFAULT_KEYBINDS, describeKeybinds, parseKeybinds } from "../core/keybind";
import { resolvePath } from "../utils/path";

export type StartupOptions = {
  configPath: string;
  /** Human-readable form of `keybinds`, for labels and /stt status. */
  keybind: string;
  /** Every key that toggles dictation. See core/keybind.ts for why there is more than one. */
  keybinds: string[];
  locale: string;
  mode: string;
};

export const DEFAULT_CONFIG_PATH = join(homedir(), ".pi", "agent", "stt.json");

const readJsonIfPresent = (path: string): Record<string, unknown> => {
  if (!path || !existsSync(path)) return {};
  return objectFrom(JSON.parse(readFileSync(path, "utf8")));
};

export const resolveStartupOptions = (): StartupOptions => {
  const envConfigPath = textFrom(process.env.PI_STT_CONFIG);
  const configPath = envConfigPath ? resolvePath(envConfigPath) : existsSync(DEFAULT_CONFIG_PATH) ? DEFAULT_CONFIG_PATH : "";
  const config = readJsonIfPresent(configPath);
  const envKeybind = textFrom(process.env.PI_STT_KEYBIND);
  const keybinds = parseKeybinds(envKeybind.length > 0 ? envKeybind : config.keybind, DEFAULT_KEYBINDS);
  const keybind = describeKeybinds(keybinds);
  const locale = textFrom(process.env.PI_STT_LOCALE, textFrom(config.locale, "en"));
  const mode = textFrom(process.env.PI_STT_MODE, textFrom(config.mode, "default"));

  return { configPath, keybind, keybinds, locale, mode };
};
