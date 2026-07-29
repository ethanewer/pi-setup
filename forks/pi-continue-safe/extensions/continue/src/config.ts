import { existsSync, readFileSync } from "node:fs";
import { mkdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import type {
	AgentGuideOverwritePolicy,
	ConfigScope,
	ContinuationConfig,
	ContinuationReasoning,
	PromptOverridePolicy,
	SynthesisFailureFallback,
	WriteMode,
} from "./types.ts";
import { resolveAgentDir } from "./agent-dir.ts";
import { writeFileAtomic } from "./atomic-write.ts";
import { queueInputWarning } from "./input-warnings.ts";

const REASONING_LEVELS = new Set<ContinuationReasoning>([
	"inherit",
	"off",
	"minimal",
	"low",
	"medium",
	"high",
	"xhigh",
]);
const PROMPT_OVERRIDE_POLICIES = new Set<PromptOverridePolicy>([
	"package-default",
	"global-override",
	"project-override",
]);
const WRITE_MODES = new Set<WriteMode>(["always", "off"]);
const AGENT_GUIDE_OVERWRITE_POLICIES = new Set<AgentGuideOverwritePolicy>(["confirm", "allow"]);
const SYNTHESIS_FAILURE_FALLBACKS = new Set<SynthesisFailureFallback>(["native-compaction", "cancel"]);
const DEFAULT_SYNTHESIS_TIMEOUT_MS = 180_000;
const DEFAULT_MAX_CHAINED_CONTINUATIONS = 10;
const DEFAULT_MAX_CHAINED_SYNTHESIS_COST_USD = 5;
const mutationQueues = new Map<string, Promise<void>>();

async function withConfigMutationQueue(path: string, work: () => Promise<void>): Promise<void> {
	const previous = mutationQueues.get(path) ?? Promise.resolve();
	const next = previous.then(work, work);
	mutationQueues.set(path, next);
	try {
		await next;
	} finally {
		if (mutationQueues.get(path) === next) mutationQueues.delete(path);
	}
}

export const DEFAULT_CONTINUE_CONFIG: ContinuationConfig = {
	enabled: true,
	summarizerModel: "inherit",
	reasoning: "inherit",
	historyMaxTokens: null,
	synthesisTimeoutMs: DEFAULT_SYNTHESIS_TIMEOUT_MS,
	continuationArtifactMode: "always",
	agentGuidePath: "AGENTS.md",
	agentGuideSyncMode: "off",
	agentGuideOverwritePolicy: "confirm",
	agentGuideAllowOutsideProject: false,
	allowSymlinkedOutputDirectory: false,
	synthesisFailureFallback: "native-compaction",
	midRunGuardEnabled: true,
	maxChainedContinuations: DEFAULT_MAX_CHAINED_CONTINUATIONS,
	maxChainedSynthesisCostUsd: DEFAULT_MAX_CHAINED_SYNTHESIS_COST_USD,
	appendCompactionMetadata: false,
	appendReadFileTags: false,
	appendModifiedFileTags: true,
	promptOverridePolicy: "project-override",
	showAfterCompact: true,
};

interface PartialContinuationConfig {
	enabled?: boolean;
	summarizerModel?: string;
	reasoning?: string;
	historyMaxTokens?: number | null;
	synthesisTimeoutMs?: number;
	continuationArtifactMode?: string;
	agentGuidePath?: string;
	agentGuideSyncMode?: string;
	agentGuideOverwritePolicy?: string;
	agentGuideAllowOutsideProject?: boolean;
	allowSymlinkedOutputDirectory?: boolean;
	synthesisFailureFallback?: string;
	midRunGuardEnabled?: boolean;
	maxChainedContinuations?: number;
	maxChainedSynthesisCostUsd?: number;
	appendCompactionMetadata?: boolean;
	appendReadFileTags?: boolean;
	appendModifiedFileTags?: boolean;
	promptOverridePolicy?: string;
	showAfterCompact?: boolean;
}

export interface ContinuationConfigPatch {
	enabled?: boolean;
	summarizerModel?: string;
	reasoning?: ContinuationReasoning;
	historyMaxTokens?: number | null;
	synthesisTimeoutMs?: number;
	continuationArtifactMode?: WriteMode;
	agentGuidePath?: string;
	agentGuideSyncMode?: WriteMode;
	agentGuideOverwritePolicy?: AgentGuideOverwritePolicy;
	agentGuideAllowOutsideProject?: boolean;
	allowSymlinkedOutputDirectory?: boolean;
	synthesisFailureFallback?: SynthesisFailureFallback;
	midRunGuardEnabled?: boolean;
	maxChainedContinuations?: number;
	maxChainedSynthesisCostUsd?: number;
	appendCompactionMetadata?: boolean;
	appendReadFileTags?: boolean;
	appendModifiedFileTags?: boolean;
	promptOverridePolicy?: PromptOverridePolicy;
	showAfterCompact?: boolean;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function asBoolean(value: unknown): boolean | undefined {
	return typeof value === "boolean" ? value : undefined;
}

function asNumber(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function asNullableNumber(value: unknown): number | null | undefined {
	if (value === null) return null;
	return asNumber(value);
}

function asString(value: unknown): string | undefined {
	return typeof value === "string" ? value : undefined;
}

function parsePartialConfig(value: unknown): PartialContinuationConfig {
	if (!isRecord(value)) return {};
	const result: PartialContinuationConfig = {};
	const enabled = asBoolean(value.enabled);
	if (enabled !== undefined) result.enabled = enabled;
	const summarizerModel = asString(value.summarizerModel);
	if (summarizerModel !== undefined) result.summarizerModel = summarizerModel;
	const reasoning = asString(value.reasoning);
	if (reasoning !== undefined) result.reasoning = reasoning;
	const historyMaxTokens = asNullableNumber(value.historyMaxTokens);
	if (historyMaxTokens !== undefined) result.historyMaxTokens = historyMaxTokens;
	const synthesisTimeoutMs = asNumber(value.synthesisTimeoutMs);
	if (synthesisTimeoutMs !== undefined) result.synthesisTimeoutMs = synthesisTimeoutMs;
	const continuationArtifactMode = asString(value.continuationArtifactMode);
	if (continuationArtifactMode !== undefined) result.continuationArtifactMode = continuationArtifactMode;
	const agentGuidePath = asString(value.agentGuidePath);
	if (agentGuidePath !== undefined) result.agentGuidePath = agentGuidePath;
	const agentGuideSyncMode = asString(value.agentGuideSyncMode);
	if (agentGuideSyncMode !== undefined) result.agentGuideSyncMode = agentGuideSyncMode;
	const agentGuideOverwritePolicy = asString(value.agentGuideOverwritePolicy);
	if (agentGuideOverwritePolicy !== undefined) result.agentGuideOverwritePolicy = agentGuideOverwritePolicy;
	const agentGuideAllowOutsideProject = asBoolean(value.agentGuideAllowOutsideProject);
	if (agentGuideAllowOutsideProject !== undefined) result.agentGuideAllowOutsideProject = agentGuideAllowOutsideProject;
	const allowSymlinkedOutputDirectory = asBoolean(value.allowSymlinkedOutputDirectory);
	if (allowSymlinkedOutputDirectory !== undefined) result.allowSymlinkedOutputDirectory = allowSymlinkedOutputDirectory;
	const synthesisFailureFallback = asString(value.synthesisFailureFallback);
	if (synthesisFailureFallback !== undefined) result.synthesisFailureFallback = synthesisFailureFallback;
	const midRunGuardEnabled = asBoolean(value.midRunGuardEnabled);
	if (midRunGuardEnabled !== undefined) result.midRunGuardEnabled = midRunGuardEnabled;
	const maxChainedContinuations = asNumber(value.maxChainedContinuations);
	if (maxChainedContinuations !== undefined) result.maxChainedContinuations = maxChainedContinuations;
	const maxChainedSynthesisCostUsd = asNumber(value.maxChainedSynthesisCostUsd);
	if (maxChainedSynthesisCostUsd !== undefined) result.maxChainedSynthesisCostUsd = maxChainedSynthesisCostUsd;
	const appendCompactionMetadata = asBoolean(value.appendCompactionMetadata);
	if (appendCompactionMetadata !== undefined) result.appendCompactionMetadata = appendCompactionMetadata;
	const appendReadFileTags = asBoolean(value.appendReadFileTags);
	if (appendReadFileTags !== undefined) result.appendReadFileTags = appendReadFileTags;
	const appendModifiedFileTags = asBoolean(value.appendModifiedFileTags);
	if (appendModifiedFileTags !== undefined) result.appendModifiedFileTags = appendModifiedFileTags;
	const promptOverridePolicy = asString(value.promptOverridePolicy);
	if (promptOverridePolicy !== undefined) result.promptOverridePolicy = promptOverridePolicy;
	const showAfterCompact = asBoolean(value.showAfterCompact);
	if (showAfterCompact !== undefined) result.showAfterCompact = showAfterCompact;
	return result;
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function readPartialConfig(path: string): PartialContinuationConfig {
	if (!existsSync(path)) return {};
	try {
		return parsePartialConfig(JSON.parse(readFileSync(path, "utf8")));
	} catch (error) {
		throw new Error(`Failed to read pi-continue config at ${path}: ${errorMessage(error)}`);
	}
}

// Runtime readers must never take the session down over an unreadable config file, so
// they degrade to the surrounding layers and report the failure once.
function readPartialConfigOrDefaults(path: string): PartialContinuationConfig {
	try {
		return readPartialConfig(path);
	} catch (error) {
		queueInputWarning(`continue-config:${path}`, `${errorMessage(error)}. pi-continue is using its remaining settings layers instead.`);
		return {};
	}
}

function normalizeReasoning(value: string | undefined): ContinuationReasoning {
	return value !== undefined && REASONING_LEVELS.has(value as ContinuationReasoning)
		? (value as ContinuationReasoning)
		: DEFAULT_CONTINUE_CONFIG.reasoning;
}

function normalizePromptOverridePolicy(value: string | undefined): PromptOverridePolicy {
	return value !== undefined && PROMPT_OVERRIDE_POLICIES.has(value as PromptOverridePolicy)
		? (value as PromptOverridePolicy)
		: DEFAULT_CONTINUE_CONFIG.promptOverridePolicy;
}

function normalizeWriteMode(value: string | undefined, fallback: WriteMode): WriteMode {
	return value !== undefined && WRITE_MODES.has(value as WriteMode)
		? (value as WriteMode)
		: fallback;
}

function normalizeAgentGuideOverwritePolicy(value: string | undefined): AgentGuideOverwritePolicy {
	return value !== undefined && AGENT_GUIDE_OVERWRITE_POLICIES.has(value as AgentGuideOverwritePolicy)
		? (value as AgentGuideOverwritePolicy)
		: DEFAULT_CONTINUE_CONFIG.agentGuideOverwritePolicy;
}

function normalizeSynthesisFailureFallback(value: string | undefined): SynthesisFailureFallback {
	return value !== undefined && SYNTHESIS_FAILURE_FALLBACKS.has(value as SynthesisFailureFallback)
		? (value as SynthesisFailureFallback)
		: DEFAULT_CONTINUE_CONFIG.synthesisFailureFallback;
}

function normalizePath(value: string | undefined, fallback: string): string {
	const trimmed = value?.trim();
	return trimmed && trimmed.length > 0 ? trimmed : fallback;
}

function normalizeTokenOverride(value: number | null | undefined): number | null {
	if (value === null || value === undefined) return null;
	const rounded = Math.round(value);
	return rounded > 0 ? rounded : null;
}

// A non-positive cap means "no ceiling", so an operator can restore unbounded chaining.
function normalizeChainCount(value: number | undefined, fallback: number): number {
	if (value === undefined) return fallback;
	const rounded = Math.floor(value);
	return Number.isFinite(rounded) && rounded > 0 ? rounded : 0;
}

function normalizeChainCost(value: number | undefined, fallback: number): number {
	if (value === undefined) return fallback;
	return Number.isFinite(value) && value > 0 ? value : 0;
}

function normalizeSummarizerModel(value: string | undefined): string {
	const trimmed = value?.trim();
	return trimmed && trimmed.length > 0 ? trimmed : DEFAULT_CONTINUE_CONFIG.summarizerModel;
}

function normalizeConfig(partial: PartialContinuationConfig): ContinuationConfig {
	return {
		enabled: partial.enabled ?? DEFAULT_CONTINUE_CONFIG.enabled,
		summarizerModel: normalizeSummarizerModel(partial.summarizerModel),
		reasoning: normalizeReasoning(partial.reasoning),
		historyMaxTokens: normalizeTokenOverride(partial.historyMaxTokens),
		synthesisTimeoutMs: normalizeTokenOverride(partial.synthesisTimeoutMs) ?? DEFAULT_CONTINUE_CONFIG.synthesisTimeoutMs,
		continuationArtifactMode: normalizeWriteMode(partial.continuationArtifactMode, DEFAULT_CONTINUE_CONFIG.continuationArtifactMode),
		agentGuidePath: normalizePath(partial.agentGuidePath, DEFAULT_CONTINUE_CONFIG.agentGuidePath),
		agentGuideSyncMode: normalizeWriteMode(partial.agentGuideSyncMode, DEFAULT_CONTINUE_CONFIG.agentGuideSyncMode),
		agentGuideOverwritePolicy: normalizeAgentGuideOverwritePolicy(partial.agentGuideOverwritePolicy),
		agentGuideAllowOutsideProject: partial.agentGuideAllowOutsideProject ?? DEFAULT_CONTINUE_CONFIG.agentGuideAllowOutsideProject,
		allowSymlinkedOutputDirectory: partial.allowSymlinkedOutputDirectory ?? DEFAULT_CONTINUE_CONFIG.allowSymlinkedOutputDirectory,
		synthesisFailureFallback: normalizeSynthesisFailureFallback(partial.synthesisFailureFallback),
		midRunGuardEnabled: partial.midRunGuardEnabled ?? DEFAULT_CONTINUE_CONFIG.midRunGuardEnabled,
		maxChainedContinuations: normalizeChainCount(partial.maxChainedContinuations, DEFAULT_CONTINUE_CONFIG.maxChainedContinuations),
		maxChainedSynthesisCostUsd: normalizeChainCost(partial.maxChainedSynthesisCostUsd, DEFAULT_CONTINUE_CONFIG.maxChainedSynthesisCostUsd),
		appendCompactionMetadata: partial.appendCompactionMetadata ?? DEFAULT_CONTINUE_CONFIG.appendCompactionMetadata,
		appendReadFileTags: partial.appendReadFileTags ?? DEFAULT_CONTINUE_CONFIG.appendReadFileTags,
		appendModifiedFileTags: partial.appendModifiedFileTags ?? DEFAULT_CONTINUE_CONFIG.appendModifiedFileTags,
		promptOverridePolicy: normalizePromptOverridePolicy(partial.promptOverridePolicy),
		showAfterCompact: partial.showAfterCompact ?? DEFAULT_CONTINUE_CONFIG.showAfterCompact,
	};
}

export function getGlobalConfigPath(): string {
	return join(resolveAgentDir(), "extensions", "pi-continue.json");
}

export function getProjectConfigPath(projectRoot: string): string {
	return join(projectRoot, ".pi", "extensions", "pi-continue.json");
}

// Where model-authored content lands, whether it lands at all, and whether the operator is asked
// first are decisions about the operator's own machine. A repo that ships a project config must not
// be able to redirect a write, switch one on, or silence the confirmation, so these keys are read
// from the user's global config only - even for a project the host reports as trusted.
export const GLOBAL_ONLY_CONFIG_KEYS = [
	"agentGuidePath",
	"agentGuideSyncMode",
	"agentGuideOverwritePolicy",
	"agentGuideAllowOutsideProject",
	"allowSymlinkedOutputDirectory",
] as const;

function reportIgnoredProjectKeys(projectRoot: string, projectConfig: PartialContinuationConfig): void {
	const values = projectConfig as Record<string, unknown>;
	const ignored = GLOBAL_ONLY_CONFIG_KEYS.filter((key) => values[key] !== undefined);
	if (ignored.length === 0) return;
	queueInputWarning(
		`project-scope-global-only:${projectRoot}:${ignored.join(",")}`,
		`pi-continue ignored project-scoped ${ignored.join(", ")} in ${getProjectConfigPath(projectRoot)}: ${ignored.length === 1 ? "that key" : "those keys"} can only be set in the global pi-continue config.`,
	);
}

/** Load effective config; project scope is honored only for a trusted project, and never for output-targeting keys. */
export function loadContinuationConfig(projectRoot: string, projectTrusted = false): ContinuationConfig {
	const globalConfig = readPartialConfigOrDefaults(getGlobalConfigPath());
	const projectConfig = projectTrusted ? readPartialConfigOrDefaults(getProjectConfigPath(projectRoot)) : {};
	reportIgnoredProjectKeys(projectRoot, projectConfig);
	const config = normalizeConfig({ ...globalConfig, ...projectConfig });
	return {
		...config,
		agentGuidePath: normalizePath(globalConfig.agentGuidePath, DEFAULT_CONTINUE_CONFIG.agentGuidePath),
		agentGuideSyncMode: normalizeWriteMode(globalConfig.agentGuideSyncMode, DEFAULT_CONTINUE_CONFIG.agentGuideSyncMode),
		agentGuideOverwritePolicy: normalizeAgentGuideOverwritePolicy(globalConfig.agentGuideOverwritePolicy),
		agentGuideAllowOutsideProject: globalConfig.agentGuideAllowOutsideProject ?? DEFAULT_CONTINUE_CONFIG.agentGuideAllowOutsideProject,
		allowSymlinkedOutputDirectory: globalConfig.allowSymlinkedOutputDirectory ?? DEFAULT_CONTINUE_CONFIG.allowSymlinkedOutputDirectory,
	};
}

export function loadScopeConfig(scope: ConfigScope, projectRoot: string): ContinuationConfig {
	return normalizeConfig(readPartialConfigOrDefaults(getConfigPath(scope, projectRoot)));
}

function serializeConfig(config: ContinuationConfig | PartialContinuationConfig): string {
	return `${JSON.stringify(config, null, 2)}\n`;
}

function getConfigPath(scope: ConfigScope, projectRoot: string): string {
	return scope === "global" ? getGlobalConfigPath() : getProjectConfigPath(projectRoot);
}

/** Persist the full config at the selected scope. */
export async function saveContinuationConfig(scope: ConfigScope, projectRoot: string, config: ContinuationConfig): Promise<void> {
	const targetPath = getConfigPath(scope, projectRoot);
	await withConfigMutationQueue(targetPath, async () => {
		await mkdir(dirname(targetPath), { recursive: true });
		// A config file is package-owned too: a symlink planted at a project-scoped config path must
		// not turn a settings edit into a write somewhere else.
		await writeFileAtomic(targetPath, serializeConfig(config), { noFollow: true });
	});
}

/** Patch only explicitly edited keys at the selected scope, preserving inherited config from broader layers. */
export async function patchContinuationConfig(scope: ConfigScope, projectRoot: string, patch: ContinuationConfigPatch): Promise<void> {
	const targetPath = getConfigPath(scope, projectRoot);
	await withConfigMutationQueue(targetPath, async () => {
		const current = readPartialConfig(targetPath);
		await mkdir(dirname(targetPath), { recursive: true });
		await writeFileAtomic(targetPath, serializeConfig({ ...current, ...patch }), { noFollow: true });
	});
}

/** Reset the selected config scope by deleting the scoped file. */
export async function resetContinuationConfig(scope: ConfigScope, projectRoot: string): Promise<void> {
	const targetPath = getConfigPath(scope, projectRoot);
	await withConfigMutationQueue(targetPath, async () => {
		if (!existsSync(targetPath)) return;
		await rm(targetPath, { force: true });
	});
}
