import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { queueInputWarning } from "./input-warnings.ts";

interface PiInternals {
	prepareCompaction: (entries: unknown[], settings: { enabled: boolean; reserveTokens: number; keepRecentTokens: number }) => unknown;
	estimateTokens: (message: unknown) => number;
	estimateContextTokens: (messages: unknown[]) => {
		tokens: number;
		usageTokens: number;
		trailingTokens: number;
		lastUsageIndex: number | null;
	};
	convertToLlm: (messages: unknown[]) => unknown[];
	serializeConversation: (messages: unknown[]) => string;
}

const INTERNALS_UNAVAILABLE_WARNING = "pi-continue could not load Pi's internal compaction helpers from the installed Pi version; automatic continuation and package-owned handoffs stay off and Pi's own compaction is used until the versions match again.";

export class PiInternalsUnavailableError extends Error {}

let cachedInternals: PiInternals | undefined;

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function requireExport<T>(module: unknown, name: string, relativePath: string): T {
	const value = isRecord(module) ? module[name] : undefined;
	if (typeof value !== "function") {
		throw new PiInternalsUnavailableError(`Pi internal export ${name} is missing from ${relativePath}`);
	}
	return value as T;
}

async function importInternalModule(distRoot: string, relativePath: string[]): Promise<unknown> {
	try {
		return await import(pathToFileURL(join(distRoot, ...relativePath)).href);
	} catch {
		throw new PiInternalsUnavailableError(`Pi internal module ${relativePath.join("/")} could not be loaded`);
	}
}

/**
 * Resolve Pi internal compaction helpers from the installed package at runtime.
 *
 * Every export is checked because the peer range is open-ended; only a fully resolved set is
 * cached, so a host that gains the exports later stops being penalized by an earlier failure.
 */
export async function loadPiInternals(): Promise<PiInternals> {
	if (cachedInternals) return cachedInternals;
	try {
		const packageEntryUrl = import.meta.resolve("@earendil-works/pi-coding-agent");
		const distRoot = dirname(fileURLToPath(packageEntryUrl));
		const [compactionModule, messagesModule, utilsModule] = await Promise.all([
			importInternalModule(distRoot, ["core", "compaction", "compaction.js"]),
			importInternalModule(distRoot, ["core", "messages.js"]),
			importInternalModule(distRoot, ["core", "compaction", "utils.js"]),
		]);
		const internals: PiInternals = {
			prepareCompaction: requireExport(compactionModule, "prepareCompaction", "core/compaction/compaction.js"),
			estimateTokens: requireExport(compactionModule, "estimateTokens", "core/compaction/compaction.js"),
			estimateContextTokens: requireExport(compactionModule, "estimateContextTokens", "core/compaction/compaction.js"),
			convertToLlm: requireExport(messagesModule, "convertToLlm", "core/messages.js"),
			serializeConversation: requireExport(utilsModule, "serializeConversation", "core/compaction/utils.js"),
		};
		cachedInternals = internals;
		return internals;
	} catch (error) {
		queueInputWarning("pi-internals", INTERNALS_UNAVAILABLE_WARNING);
		if (error instanceof PiInternalsUnavailableError) throw error;
		throw new PiInternalsUnavailableError("Pi internal compaction helpers could not be resolved");
	}
}
