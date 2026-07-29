import type { Api, Model } from "@earendil-works/pi-ai";
import { getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { loadHistoryPromptAssets } from "./assets.ts";
import { normalizeCompactionPreparation, snapshotFileOperations, stripCompactionPreparationMessages, type ContinuationCompactionPreparation } from "./compaction-preparation.ts";
import { CONTINUATION_PROMPT } from "./continuation-prompt.ts";
import { GLOBAL_ONLY_CONFIG_KEYS, loadContinuationConfig, loadScopeConfig, patchContinuationConfig, resetContinuationConfig } from "./config.ts";
import { warnInputOnce } from "./input-warnings.ts";
import { showLatestContinuationLedger, type ContinuationLedgerOverlayController } from "./ledger-viewer.ts";
import { showScrollableTextOverlay } from "./text-viewer.ts";
import { readEffectivePiCompactionSettings } from "./pi-settings.ts";
import { renderHandoffTrigger, updateHandoffTriggerFromDialog } from "./pi-threshold-settings.ts";
import { loadPiInternals } from "./pi-internals.ts";
import { isContinuationPromptUserMessage } from "./prompt-dispatch.ts";
import { compileHistoryPrompt, renderPromptPreview } from "./prompt.ts";
import { resolveProjectContext } from "./project.ts";
import { isProjectScopeTrusted } from "./project-trust.ts";
import { resolveSummarizerModel } from "./model-settings.ts";
import { getLatestContinuationEvent, getLatestContinuationLedger, type ContinuationRuntimeState } from "./runtime.ts";
import { renderStatus } from "./status.ts";
import { commandHasUi } from "./ui.ts";
import type { ConfigScope, ContinuationConfig, PreviewPayload } from "./types.ts";

interface ParsedScope {
	scope: ConfigScope;
	error: string | undefined;
}

function parseScope(args: string | undefined, command: "settings" | "reset"): ParsedScope {
	const trimmed = args?.trim().toLowerCase() ?? "";
	if (trimmed.length === 0) return { scope: "project", error: undefined };
	if (trimmed === "project" || trimmed === "global") return { scope: trimmed, error: undefined };
	return { scope: "project", error: `Usage: /continue ${command} [project|global]` };
}

function joinArgs(args: string | undefined): string | undefined {
	const trimmed = args?.trim();
	return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

async function requireUi(ctx: ExtensionCommandContext): Promise<boolean> {
	return commandHasUi(ctx);
}

async function buildPromptPreviewPayload(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
	customInstructions: string | undefined,
): Promise<PreviewPayload | undefined> {
	const sessionId = ctx.sessionManager.getSessionId();
	const initialProjectContext = await resolveProjectContext(pi, ctx.cwd, sessionId);
	const projectTrusted = isProjectScopeTrusted(ctx, initialProjectContext.projectRoot);
	const config = loadContinuationConfig(initialProjectContext.projectRoot, projectTrusted);
	const projectContext = await resolveProjectContext(pi, ctx.cwd, sessionId, config.agentGuidePath, config.agentGuideAllowOutsideProject);
	// A preview that silently omits the guide would look like a repo without one.
	if (projectContext.agentGuideReadRefusal) warnInputOnce(ctx, `agent-guide-read:${projectContext.agentGuidePath}`, projectContext.agentGuideReadRefusal);
	const piCompactionSettings = readEffectivePiCompactionSettings(projectContext.projectRoot, projectTrusted);
	// Status and preview must still render when the installed Pi no longer exposes the internals.
	const internals = await loadPiInternals().catch(() => undefined);
	if (!internals) return undefined;
	const branchEntries = ctx.sessionManager.getBranch();
	const rawPreparation = internals.prepareCompaction(branchEntries, piCompactionSettings) as ContinuationCompactionPreparation | undefined;
	if (!rawPreparation) return undefined;
	const preparation = stripCompactionPreparationMessages(
		normalizeCompactionPreparation(rawPreparation, branchEntries),
		(message) => isContinuationPromptUserMessage(message, CONTINUATION_PROMPT),
	);
	const scenario = preparation.previousSummary ? "update" : "initial";
	const historyTranscript = internals.serializeConversation(internals.convertToLlm(preparation.messagesToSummarize));
	const turnPrefixTranscript = preparation.isSplitTurn && preparation.turnPrefixMessages.length > 0
		? internals.serializeConversation(internals.convertToLlm(preparation.turnPrefixMessages))
		: undefined;
	const fileOps = snapshotFileOperations(preparation.fileOps);
	const historyAssets = loadHistoryPromptAssets(projectContext.projectRoot, config.promptOverridePolicy, scenario, projectTrusted);
	const history = compileHistoryPrompt(historyAssets, {
		scenario,
		projectRoot: projectContext.projectRoot,
		agentGuidePath: projectContext.agentGuidePath,
		existingAgentGuide: projectContext.existingAgentGuide,
		previousSummary: preparation.previousSummary,
		historyTranscript,
		turnPrefixTranscript,
		customInstructions,
		fileOps,
	});
	return {
		history,
		scenario,
		isSplitTurn: preparation.isSplitTurn,
	};
}

async function showText(ctx: ExtensionCommandContext, title: string, content: string): Promise<void> {
	if (!(await requireUi(ctx))) return;
	const shown = await showScrollableTextOverlay(ctx, { title, content });
	if (!shown) ctx.ui.notify(`${title} panel cannot open in this Pi mode.`, "warning");
}

async function chooseModel(ctx: ExtensionCommandContext): Promise<string | undefined> {
	const options = ["Inherit current model", ...ctx.modelRegistry.getAvailable().map((model) => `${model.provider}/${model.id}`), "Enter provider/model manually"];
	const selected = await ctx.ui.select("Handoff model", options);
	if (!selected) return undefined;
	if (selected === "Inherit current model") return "inherit";
	if (selected === "Enter provider/model manually") {
		const entered = await ctx.ui.input("Handoff model", "provider/model or inherit");
		return entered?.trim();
	}
	return selected;
}

const ALL_REASONING_OPTIONS: readonly ContinuationConfig["reasoning"][] = ["inherit", "off", "minimal", "low", "medium", "high", "xhigh"];

/** Return operator-selectable reasoning levels, hiding levels unsupported by the resolved summarizer model. */
export function getReasoningOptionsForModel(model: Model<Api> | undefined): ContinuationConfig["reasoning"][] {
	if (!model) return [...ALL_REASONING_OPTIONS];
	return ["inherit", ...getSupportedThinkingLevels(model)];
}

async function chooseReasoning(ctx: ExtensionCommandContext, config: ContinuationConfig): Promise<ContinuationConfig["reasoning"] | undefined> {
	const selected = await ctx.ui.select("Reasoning level", getReasoningOptionsForModel(resolveSummarizerModel(ctx, config)));
	return selected as ContinuationConfig["reasoning"] | undefined;
}


async function chooseTokenOverride(
	ctx: ExtensionCommandContext,
	title: string,
	current: number | null,
): Promise<number | null | undefined> {
	const choice = await ctx.ui.select(title, ["Use Pi default", `Keep current (${current ?? "Pi default"})`, "Enter token limit"]);
	if (!choice) return undefined;
	if (choice === "Use Pi default") return null;
	if (choice.startsWith("Keep current")) return current;
	const entered = await ctx.ui.input(title, "positive integer or blank to cancel");
	if (!entered) return undefined;
	const parsed = Number.parseInt(entered, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

async function choosePositiveInteger(
	ctx: ExtensionCommandContext,
	title: string,
	current: number,
): Promise<number | undefined> {
	const choice = await ctx.ui.select(title, [`Keep current (${current})`, "Enter positive integer"]);
	if (!choice || choice.startsWith("Keep current")) return undefined;
	const entered = await ctx.ui.input(title, "positive integer or blank to cancel");
	if (!entered) return undefined;
	const parsed = Number.parseInt(entered, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

function renderChainLimit(value: number): string {
	return value > 0 ? `${value} automatic continuations` : "no limit";
}

function renderChainCostLimit(value: number): string {
	return value > 0 ? `$${value}` : "no limit";
}

async function chooseChainLimit(
	ctx: ExtensionCommandContext,
	title: string,
	current: number,
): Promise<number | undefined> {
	const choice = await ctx.ui.select(title, [`Keep current (${current > 0 ? current : "no limit"})`, "Enter limit", "Remove limit"]);
	if (!choice || choice.startsWith("Keep current")) return undefined;
	if (choice === "Remove limit") return 0;
	const entered = await ctx.ui.input(title, "positive number, 0 for no limit, or blank to cancel");
	if (!entered) return undefined;
	const parsed = Number.parseFloat(entered.trim());
	return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined;
}

const CONFIG_KEYS = [
	"enabled",
	"summarizerModel",
	"reasoning",
	"historyMaxTokens",
	"synthesisTimeoutMs",
	"continuationArtifactMode",
	"agentGuidePath",
	"agentGuideSyncMode",
	"agentGuideOverwritePolicy",
	"synthesisFailureFallback",
	"midRunGuardEnabled",
	"maxChainedContinuations",
	"maxChainedSynthesisCostUsd",
	"appendCompactionMetadata",
	"appendReadFileTags",
	"appendModifiedFileTags",
	"promptOverridePolicy",
	"showAfterCompact",
] as const;

function setConfigPatchValue<Key extends keyof ContinuationConfig>(patch: Partial<ContinuationConfig>, key: Key, value: ContinuationConfig[Key]): void {
	patch[key] = value;
}

function diffConfig(previous: ContinuationConfig, next: ContinuationConfig): Partial<ContinuationConfig> {
	const patch: Partial<ContinuationConfig> = {};
	for (const key of CONFIG_KEYS) {
		if (previous[key] !== next[key]) setConfigPatchValue(patch, key, next[key]);
	}
	return patch;
}

// A key that decides where model-authored content lands, or whether the operator is asked first,
// is only honored from the global layer, so a project-scope edit is saved but tells the operator
// where it has to be set to take effect.
function notifyGlobalOnlyEdit(ctx: ExtensionCommandContext, scope: ConfigScope, patch: Partial<ContinuationConfig>): void {
	if (scope !== "project") return;
	const globalOnly = GLOBAL_ONLY_CONFIG_KEYS.filter((key) => patch[key] !== undefined);
	if (globalOnly.length === 0) return;
	ctx.ui.notify(
		`${globalOnly.join(", ")} is only honored from global settings; switch the settings scope to global to change it for real.`,
		"warning",
	);
}

async function updateSetting(
	ctx: ExtensionCommandContext,
	scope: ConfigScope,
	projectRoot: string,
	config: ContinuationConfig,
	mutator: (current: ContinuationConfig) => Promise<ContinuationConfig | undefined>,
): Promise<ContinuationConfig> {
	const next = await mutator(config);
	if (!next) return config;
	const patch = diffConfig(config, next);
	try {
		await patchContinuationConfig(scope, projectRoot, patch);
	} catch (error) {
		// A config file that cannot be written - a symlink the package refuses to write through, a
		// read-only directory - must report itself instead of aborting the settings dialog, and the
		// dialog must keep showing the value that is actually stored.
		ctx.ui.notify(`Could not save ${scope} continuation settings: ${error instanceof Error ? error.message : String(error)}`, "error");
		return config;
	}
	notifyGlobalOnlyEdit(ctx, scope, patch);
	return next;
}

function notifyUntrustedEditScope(ctx: ExtensionCommandContext, scope: ConfigScope, projectTrusted: boolean): void {
	if (scope !== "project" || projectTrusted) return;
	ctx.ui.notify("Project settings are saved but stay inactive until this project is trusted.", "warning");
}

/** Edit scoped config in the TUI. */
export async function runSettingsDialog(pi: ExtensionAPI, ctx: ExtensionCommandContext, args: string | undefined): Promise<void> {
	if (!(await requireUi(ctx))) return;
	const projectContext = await resolveProjectContext(pi, ctx.cwd, ctx.sessionManager.getSessionId());
	const parsedScope = parseScope(args, "settings");
	if (parsedScope.error) {
		ctx.ui.notify(parsedScope.error, "warning");
		return;
	}
	const projectTrusted = isProjectScopeTrusted(ctx, projectContext.projectRoot);
	let scope = parsedScope.scope;
	let config = loadScopeConfig(scope, projectContext.projectRoot);
	notifyUntrustedEditScope(ctx, scope, projectTrusted);
	while (true) {
		const selected = await ctx.ui.select("Continuation settings", [
			`Settings scope: ${scope}`,
			`Enabled: ${config.enabled ? "yes" : "no"}`,
			`Handoff model: ${config.summarizerModel}`,
			`Reasoning: ${config.reasoning}`,
			`History output budget: ${config.historyMaxTokens ?? "Pi default"}`,
			`Synthesis timeout: ${config.synthesisTimeoutMs} ms`,
			`Continuation artifact: ${config.continuationArtifactMode}`,
			`Agent guide path: ${config.agentGuidePath}`,
			`Agent guide updates: ${config.agentGuideSyncMode} (full replacement only)`,
			`Agent guide overwrite: ${config.agentGuideOverwritePolicy}`,
			`Synthesis failure fallback: ${config.synthesisFailureFallback}`,
			`Automatic mid-run continuation: ${config.midRunGuardEnabled ? "yes" : "no"}`,
			`Chained continuation limit: ${renderChainLimit(config.maxChainedContinuations)}`,
			`Chained synthesis cost limit: ${renderChainCostLimit(config.maxChainedSynthesisCostUsd)}`,
			`Handoff trigger: ${renderHandoffTrigger(ctx, scope, projectContext.projectRoot, projectTrusted)}`,
			`Append compaction metadata: ${config.appendCompactionMetadata ? "yes" : "no"}`,
			`Append read file tags: ${config.appendReadFileTags ? "yes" : "no"}`,
			`Append modified file tags: ${config.appendModifiedFileTags ? "yes" : "no"}`,
			`Prompt override policy: ${config.promptOverridePolicy}`,
			`Show brief after compaction: ${config.showAfterCompact ? "yes" : "no"}`,
			`Reset ${scope} settings`,
			"Done",
		]);
		if (!selected || selected === "Done") return;
		if (selected.startsWith("Settings scope:")) {
			scope = scope === "project" ? "global" : "project";
			config = loadScopeConfig(scope, projectContext.projectRoot);
			ctx.ui.notify(`Editing ${scope} continuation settings`, "info");
			notifyUntrustedEditScope(ctx, scope, projectTrusted);
			continue;
		}
		if (selected.startsWith("Enabled:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => ({
				...current,
				enabled: !current.enabled,
			}));
			continue;
		}
		if (selected.startsWith("Handoff model:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await chooseModel(ctx);
				return next ? { ...current, summarizerModel: next } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Reasoning:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await chooseReasoning(ctx, current);
				return next ? { ...current, reasoning: next } : undefined;
			});
			continue;
		}
		if (selected.startsWith("History output budget:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await chooseTokenOverride(ctx, "History output budget", current.historyMaxTokens);
				return next !== undefined ? { ...current, historyMaxTokens: next } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Synthesis timeout:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await choosePositiveInteger(ctx, "Synthesis timeout in milliseconds", current.synthesisTimeoutMs);
				return next !== undefined ? { ...current, synthesisTimeoutMs: next } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Continuation artifact:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await ctx.ui.select("Continuation artifact", ["always", "off"]);
				return next ? { ...current, continuationArtifactMode: next as ContinuationConfig["continuationArtifactMode"] } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Agent guide path:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await ctx.ui.input("Agent guide path", "repo-relative path, default AGENTS.md");
				return next?.trim() ? { ...current, agentGuidePath: next.trim() } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Agent guide updates:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await ctx.ui.select("Agent guide sync", ["off", "always"]);
				return next ? { ...current, agentGuideSyncMode: next as ContinuationConfig["agentGuideSyncMode"] } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Agent guide overwrite:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await ctx.ui.select("Agent guide overwrite", ["confirm", "allow"]);
				return next ? { ...current, agentGuideOverwritePolicy: next as ContinuationConfig["agentGuideOverwritePolicy"] } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Synthesis failure fallback:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await ctx.ui.select("Synthesis failure fallback", ["native-compaction", "cancel"]);
				return next ? { ...current, synthesisFailureFallback: next as ContinuationConfig["synthesisFailureFallback"] } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Automatic mid-run continuation:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => ({
				...current,
				midRunGuardEnabled: !current.midRunGuardEnabled,
			}));
			continue;
		}
		if (selected.startsWith("Chained continuation limit:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await chooseChainLimit(ctx, "Chained automatic continuations", current.maxChainedContinuations);
				return next !== undefined ? { ...current, maxChainedContinuations: next } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Chained synthesis cost limit:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await chooseChainLimit(ctx, "Chained synthesis cost limit in USD", current.maxChainedSynthesisCostUsd);
				return next !== undefined ? { ...current, maxChainedSynthesisCostUsd: next } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Handoff trigger:")) {
			await updateHandoffTriggerFromDialog(ctx, scope, projectContext.projectRoot, projectTrusted);
			continue;
		}
		if (selected.startsWith("Append compaction metadata:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => ({
				...current,
				appendCompactionMetadata: !current.appendCompactionMetadata,
			}));
			continue;
		}
		if (selected.startsWith("Append read file tags:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => ({
				...current,
				appendReadFileTags: !current.appendReadFileTags,
			}));
			continue;
		}
		if (selected.startsWith("Append modified file tags:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => ({
				...current,
				appendModifiedFileTags: !current.appendModifiedFileTags,
			}));
			continue;
		}
		if (selected.startsWith("Prompt override policy:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => {
				const next = await ctx.ui.select("Prompt override policy", ["package-default", "global-override", "project-override"]);
				return next ? { ...current, promptOverridePolicy: next as ContinuationConfig["promptOverridePolicy"] } : undefined;
			});
			continue;
		}
		if (selected.startsWith("Show brief after compaction:")) {
			config = await updateSetting(ctx, scope, projectContext.projectRoot, config, async (current) => ({
				...current,
				showAfterCompact: !current.showAfterCompact,
			}));
			continue;
		}
		if (selected === `Reset ${scope} settings`) {
			const confirmed = await ctx.ui.confirm(`Reset ${scope} settings?`, `Delete the ${scope} settings file and fall back to global/default settings?`);
			if (confirmed) {
				await resetContinuationConfig(scope, projectContext.projectRoot);
				config = loadScopeConfig(scope, projectContext.projectRoot);
				ctx.ui.notify(`Reset ${scope} continuation settings`, "info");
			}
		}
	}
}

/** Show effective config and prompt provenance. */
export async function runStatusCommand(pi: ExtensionAPI, ctx: ExtensionCommandContext, runtime: ContinuationRuntimeState): Promise<void> {
	if (!(await requireUi(ctx))) return;
	const sessionId = ctx.sessionManager.getSessionId();
	const initialProjectContext = await resolveProjectContext(pi, ctx.cwd, sessionId);
	const projectTrusted = isProjectScopeTrusted(ctx, initialProjectContext.projectRoot);
	const config = loadContinuationConfig(initialProjectContext.projectRoot, projectTrusted);
	const projectContext = await resolveProjectContext(pi, ctx.cwd, sessionId, config.agentGuidePath, config.agentGuideAllowOutsideProject);
	const payload = await buildPromptPreviewPayload(pi, ctx, undefined);
	await showText(
		ctx,
		"continuation status",
		renderStatus(
			ctx,
			config,
			projectContext.projectRoot,
			projectContext.continuationArtifactPath,
			projectContext.agentGuidePath,
			payload,
			getLatestContinuationEvent(runtime),
			projectTrusted,
		),
	);
}

/** Show the latest in-memory Continuation Ledger without mutating the transcript. */
export async function runLedgerCommand(ctx: ExtensionCommandContext, runtime: ContinuationRuntimeState, ledgerOverlay: ContinuationLedgerOverlayController): Promise<void> {
	await showLatestContinuationLedger(ctx, getLatestContinuationLedger(runtime), ledgerOverlay);
}

/** Reset scoped config. */
export async function runResetCommand(pi: ExtensionAPI, ctx: ExtensionCommandContext, args: string | undefined): Promise<void> {
	if (!(await requireUi(ctx))) return;
	const projectContext = await resolveProjectContext(pi, ctx.cwd, ctx.sessionManager.getSessionId());
	const parsedScope = parseScope(args, "reset");
	if (parsedScope.error) {
		ctx.ui.notify(parsedScope.error, "warning");
		return;
	}
	const scope = parsedScope.scope;
	const confirmed = await ctx.ui.confirm(`Reset ${scope} settings?`, `Delete the ${scope} settings file and fall back to global/default settings?`);
	if (!confirmed) return;
	await resetContinuationConfig(scope, projectContext.projectRoot);
	ctx.ui.notify(`Reset ${scope} continuation settings`, "info");
}

/** Preview handoff prompts. */
export async function runPreviewCommand(pi: ExtensionAPI, ctx: ExtensionCommandContext, args: string | undefined): Promise<void> {
	if (!(await requireUi(ctx))) return;
	const payload = await buildPromptPreviewPayload(pi, ctx, joinArgs(args));
	if (!payload) {
		ctx.ui.notify("No handoff preview is available.", "warning");
		return;
	}
	const section = renderPromptPreview(`Handoff prompt (${payload.scenario})`, payload.history);
	await showText(ctx, "handoff prompt preview", section);
}
