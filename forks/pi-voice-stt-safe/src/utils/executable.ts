import { accessSync, constants, statSync } from "node:fs";
import { access, realpath, stat } from "node:fs/promises";
import { delimiter, extname, isAbsolute, resolve } from "node:path";
import { textFrom } from "./coerce";
import { resolvePath } from "./path";

const looksLikePath = (command: string): boolean => command.includes("/") || command.includes("\\") || command.startsWith("~");

const withWindowsExtensions = (candidate: string): string[] => {
  if (process.platform !== "win32" || extname(candidate)) return [candidate];
  const extensions = textFrom(process.env.PATHEXT, ".COM;.EXE;.BAT;.CMD")
    .split(";")
    .map((extension) => extension.trim())
    .filter(Boolean);
  return [candidate, ...extensions.map((extension) => `${candidate}${extension}`)];
};

const candidatesFor = (command: string): string[] => {
  const bases = looksLikePath(command)
    ? [resolvePath(command)]
    : textFrom(process.env.PATH).split(delimiter).filter(Boolean).map((directory) => resolve(directory, command));
  return bases.flatMap(withWindowsExtensions);
};

const isExecutableFile = async (candidate: string): Promise<boolean> => {
  try {
    if (!(await stat(candidate)).isFile()) return false;
    await access(candidate, constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

/**
 * Resolve a configured program name or path to an absolute realpath that exists
 * and is a regular executable file, so callers spawn a known binary instead of
 * whatever the name happens to hit at run time.
 */
export const resolveExecutablePath = async (command: string, label: string): Promise<string> => {
  if (!command) throw new Error(`${label} is empty.`);

  for (const candidate of candidatesFor(command)) {
    if (await isExecutableFile(candidate)) return realpath(candidate);
  }

  if (looksLikePath(command)) {
    throw new Error(`${label} is not an executable file: ${resolvePath(command)}`);
  }
  throw new Error(`${label} was not found as an executable in PATH: ${command}`);
};

/** Synchronous re-check at spawn time for an already resolved absolute path. */
export const assertExecutablePath = (command: string, label: string): void => {
  if (!isAbsolute(command)) throw new Error(`${label} must be an absolute path, got: ${command}`);

  try {
    if (!statSync(command).isFile()) throw new Error("not a regular file");
    accessSync(command, constants.X_OK);
  } catch {
    throw new Error(`${label} is not an executable file: ${command}`);
  }
};
