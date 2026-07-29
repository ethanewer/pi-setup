import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Pi normalizes PI_CODING_AGENT_DIR before use, so the same value must not resolve to a
// literal "~" directory here.
function expandAgentDir(value: string): string {
	const home = homedir();
	if (value === "~") return home;
	if (value.startsWith("~/") || (process.platform === "win32" && value.startsWith("~\\"))) {
		return join(home, value.slice(2));
	}
	if (/^file:\/\//.test(value)) return fileURLToPath(value);
	return value;
}

/** Resolve Pi's agent config directory for package config, settings, and prompt overrides. */
export function resolveAgentDir(): string {
	const configured = process.env.PI_CODING_AGENT_DIR;
	return configured ? expandAgentDir(configured) : join(homedir(), ".pi", "agent");
}
