import { existsSync, readFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { ConfigScope, PiCompactionSettings } from "./types.ts";
import { resolveAgentDir } from "./agent-dir.ts";
import { writeFileAtomic } from "./atomic-write.ts";
import { queueInputWarning } from "./input-warnings.ts";

// Mirrors Pi core DEFAULT_COMPACTION_SETTINGS in @earendil-works/pi-coding-agent 0.74+.
const DEFAULT_PI_COMPACTION_SETTINGS: PiCompactionSettings = {
	enabled: true,
	reserveTokens: 16384,
	keepRecentTokens: 20000,
};
const mutationQueues = new Map<string, Promise<void>>();

export interface PiCompactionSettingsPatch {
	reserveTokens?: number | null;
}

async function withPiSettingsMutationQueue(path: string, work: () => Promise<void>): Promise<void> {
	const previous = mutationQueues.get(path) ?? Promise.resolve();
	const next = previous.then(work, work);
	mutationQueues.set(path, next);
	try {
		await next;
	} finally {
		if (mutationQueues.get(path) === next) mutationQueues.delete(path);
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asNumber(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function readJson(path: string): unknown {
	if (!existsSync(path)) return undefined;
	try {
		return JSON.parse(readFileSync(path, "utf8"));
	} catch (error) {
		throw new Error(`Failed to read Pi settings at ${path}: ${errorMessage(error)}`);
	}
}

function readSettingsRecord(path: string): Record<string, unknown> {
	const payload = readJson(path);
	if (payload === undefined) return {};
	if (!isRecord(payload)) throw new Error(`Failed to read Pi settings at ${path}: expected a JSON object`);
	return { ...payload };
}

function normalizePositiveTokenCount(value: number): number {
	const rounded = Math.round(value);
	if (!Number.isFinite(value) || !Number.isSafeInteger(rounded) || rounded <= 0) {
		throw new Error("Pi compaction reserveTokens must be a positive safe integer token count");
	}
	return rounded;
}

function getPiSettingsPath(scope: ConfigScope, projectRoot: string): string {
	return scope === "global" ? join(resolveAgentDir(), "settings.json") : join(projectRoot, ".pi", "settings.json");
}

// Runtime readers must never take the session down over an unreadable settings file, so
// they degrade to Pi's defaults and report the failure once.
function readCompactionConfig(path: string): Partial<PiCompactionSettings> {
	let payload: unknown;
	try {
		payload = readJson(path);
	} catch (error) {
		queueInputWarning(`pi-settings:${path}`, `${errorMessage(error)}. pi-continue is using Pi's default compaction settings instead.`);
		return {};
	}
	if (!isRecord(payload) || !isRecord(payload.compaction)) return {};
	return {
		enabled: typeof payload.compaction.enabled === "boolean" ? payload.compaction.enabled : undefined,
		reserveTokens: asNumber(payload.compaction.reserveTokens),
		keepRecentTokens: asNumber(payload.compaction.keepRecentTokens),
	};
}

function readCompactionSettingsRecord(settings: Record<string, unknown>, path: string): Record<string, unknown> {
	const existingCompaction = settings.compaction;
	if (existingCompaction === undefined) return {};
	if (!isRecord(existingCompaction)) {
		throw new Error(`Failed to read Pi settings at ${path}: compaction must be a JSON object`);
	}
	return { ...existingCompaction };
}

function mergeCompactionSettings(configs: Partial<PiCompactionSettings>[]): PiCompactionSettings {
	let enabled = DEFAULT_PI_COMPACTION_SETTINGS.enabled;
	let reserveTokens = DEFAULT_PI_COMPACTION_SETTINGS.reserveTokens;
	let keepRecentTokens = DEFAULT_PI_COMPACTION_SETTINGS.keepRecentTokens;
	for (const config of configs) {
		enabled = config.enabled ?? enabled;
		reserveTokens = config.reserveTokens ?? reserveTokens;
		keepRecentTokens = config.keepRecentTokens ?? keepRecentTokens;
	}
	return { enabled, reserveTokens, keepRecentTokens };
}

/** Read Pi core compaction settings as they apply to the selected scope; project scope needs trust. */
export function readPiCompactionSettingsForScope(scope: ConfigScope, projectRoot: string, projectTrusted = false): PiCompactionSettings {
	const globalConfig = readCompactionConfig(getPiSettingsPath("global", projectRoot));
	if (scope === "global" || !projectTrusted) return mergeCompactionSettings([globalConfig]);
	const projectConfig = readCompactionConfig(getPiSettingsPath("project", projectRoot));
	return mergeCompactionSettings([globalConfig, projectConfig]);
}

/** Read effective Pi core compaction settings from global and trusted-project settings files. */
export function readEffectivePiCompactionSettings(projectRoot: string, projectTrusted = false): PiCompactionSettings {
	return readPiCompactionSettingsForScope("project", projectRoot, projectTrusted);
}

/** Patch Pi-owned compaction settings at the selected scope while preserving unrelated settings. */
export async function patchPiCompactionSettings(scope: ConfigScope, projectRoot: string, patch: PiCompactionSettingsPatch): Promise<void> {
	const targetPath = getPiSettingsPath(scope, projectRoot);
	await withPiSettingsMutationQueue(targetPath, async () => {
		const hadFile = existsSync(targetPath);
		const settings = readSettingsRecord(targetPath);
		const compaction = readCompactionSettingsRecord(settings, targetPath);
		if (patch.reserveTokens !== undefined) {
			if (patch.reserveTokens === null) {
				delete compaction.reserveTokens;
			} else {
				compaction.reserveTokens = normalizePositiveTokenCount(patch.reserveTokens);
			}
		}
		if (Object.keys(compaction).length > 0) {
			settings.compaction = compaction;
		} else {
			delete settings.compaction;
		}
		if (!hadFile && Object.keys(settings).length === 0) return;
		await mkdir(dirname(targetPath), { recursive: true });
		await writeFileAtomic(targetPath, `${JSON.stringify(settings, null, 2)}\n`);
	});
}
