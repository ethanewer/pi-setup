import { randomUUID } from "node:crypto";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CONTINUATION_PROMPT } from "./continuation-prompt.ts";
import {
	beginContinuationEvent,
	finishContinuationEvent,
	isActiveRunningContinuationEvent,
	markContinuationResumeStarted,
	recordBlockedContinuationEvent,
	settleContinuationResume,
} from "./continuation-event.ts";
import { warnInputOnce } from "./input-warnings.ts";
import type {
	ContinuationEventSource,
	ContinuationLatestEvent,
	ContinuationLedgerSnapshot,
	ContinuationResumeStatus,
	MidRunGuardTrigger,
} from "./types.ts";
import {
	clearPendingResumeDispatch,
	clearResumeStartTimeout,
	markContinuationCompactionComplete,
	notify,
	preparePendingResumeDispatch,
	type ResumeProofRuntimeState,
} from "./resume-proof.ts";
import {
	beginWorkingVisuals,
	settleWorkingVisuals,
} from "./working-ui.ts";

export { CONTINUATION_PROMPT } from "./continuation-prompt.ts";
export { acceptContinuationCompactionProof, armDeferredResumeStartTimeout, clearResumeStartTimeout, dispatchVerifiedContinuationResume, failContinuationCompactionProof, verifyContinuationCompactionProof } from "./resume-proof.ts";

export type ContinuationRequestMode = "steer" | "queue";
export type ContinuationRequestSource = ContinuationEventSource;

/** One-shot correlation record for a compaction this package asked Pi to run. */
export interface ContinuationCompactionRequest {
	eventId: string;
	nonce: string;
}

/** A compaction request marker split from the operator instructions it travelled with. */
export interface ContinuationCompactionInstructions {
	nonce: string | undefined;
	instructions: string | undefined;
}

export interface ContinuationRuntimeState extends ResumeProofRuntimeState {
	latestLedger: ContinuationLedgerSnapshot | undefined;
	lastNoCompactableGuardKey: string | undefined;
	pendingCompactionRequest: ContinuationCompactionRequest | undefined;
	chainedContinuationCount: number;
	chainedSynthesisCostUsd: number;
}

/** Ceilings on automatic continuations chained without new operator input. */
export interface ContinuationChainLimits {
	maxChainedContinuations: number;
	maxChainedSynthesisCostUsd: number;
}

export interface ContinuationRequest {
	mode: ContinuationRequestMode;
	instructions: string | undefined;
}

export interface StartContinuationCompactionOptions {
	source: ContinuationRequestSource;
	instructions: string | undefined;
	trigger: MidRunGuardTrigger | undefined;
	abortActiveRun: boolean;
	continueAfterComplete: boolean;
	sendContinuation: (prompt: string) => void | Promise<void>;
	onContinuationFailed?: (eventId: string) => void;
	resumeStartTimeoutMs?: number;
	compactionProofTimeoutMs?: number;
	chainLimits?: ContinuationChainLimits;
}

export interface ContinuationResumeSettlement {
	eventId: string;
	status: Exclude<ContinuationResumeStatus, "not-requested" | "pending" | "running">;
}

const MODE_TOKENS = new Set<string>(["steer", "queue"]);
// Pi reports no id on session_before_compact, so a package-requested compaction carries its own
// one-shot marker through the custom instructions it was started with.
const COMPACTION_REQUEST_MARKER = "pi-continue-compaction-request";
const COMPACTION_REQUEST_MARKER_PATTERN = new RegExp(`^${COMPACTION_REQUEST_MARKER}:\\s*(\\S+)$`);
const RESUME_START_TIMEOUT_MS = 30_000;
const BLOCKED_RETRY_FAILURE = "Repeated over-limit retry was blocked after a failed continuation.";
const QUEUED_MESSAGES_MOVED_WARNING = "pi-continue stopped the running turn; Pi moved any queued messages into the editor draft, so they were not sent.";
const COMPACTION_FAILURE = "Continuation handoff failed.";
const RESUME_ABORTED_FAILURE = "Continuation resume was aborted.";
const RESUME_LIMIT_FAILURE = "Continuation resume stopped before completing because a model limit was reached.";
const RESUME_NO_ASSISTANT_FAILURE = "Continuation resume did not produce an assistant response.";
const CHAINED_CONTINUATION_STOP_REASON = "chained-continuation";

function isContinuationRequestMode(value: string): value is ContinuationRequestMode {
	return MODE_TOKENS.has(value);
}

function mergeInstructions(parts: (string | undefined)[]): string | undefined {
	const merged = parts
		.map((part) => part?.trim())
		.filter((part): part is string => part !== undefined && part.length > 0)
		.join("\n\n");
	return merged.length > 0 ? merged : undefined;
}

/** Parse the canonical /continue command contract. */
export function parseContinuationRequest(args: string | undefined): ContinuationRequest {
	const trimmed = args?.trim() ?? "";
	if (!trimmed) return { mode: "steer", instructions: undefined };
	const spaceIndex = trimmed.search(/\s/);
	const first = spaceIndex === -1 ? trimmed : trimmed.slice(0, spaceIndex);
	const normalizedFirst = first.toLowerCase();
	if (!isContinuationRequestMode(normalizedFirst)) return { mode: "steer", instructions: trimmed };
	const rest = spaceIndex === -1 ? "" : trimmed.slice(spaceIndex + 1).trim();
	return {
		mode: normalizedFirst,
		instructions: rest.length > 0 ? rest : undefined,
	};
}

export function createContinuationRuntimeState(): ContinuationRuntimeState {
	return {
		compactionRunning: false,
		guardFailureKey: undefined,
		awaitingResumeEventId: undefined,
		awaitingResumeStart: undefined,
		resumeStartTimeout: undefined,
		compactionProofTimeout: undefined,
		resumeDispatchTimeout: undefined,
		pendingResumeDispatch: undefined,
		resumeStartTimeoutIsBackstop: false,
		latestLedger: undefined,
		lastNoCompactableGuardKey: undefined,
		pendingCompactionRequest: undefined,
		chainedContinuationCount: 0,
		chainedSynthesisCostUsd: 0,
		latestEvent: undefined,
		activeEventId: undefined,
		nextEventSequence: 0,
	};
}

/** Tag the custom instructions of a compaction this package is about to request. */
export function buildContinuationCompactionInstructions(instructions: string | undefined, nonce: string): string {
	const marker = `${COMPACTION_REQUEST_MARKER}: ${nonce}`;
	return mergeInstructions([instructions, marker]) ?? marker;
}

/** Split the package request marker from the operator instructions a compaction carries. */
export function parseContinuationCompactionInstructions(customInstructions: string | undefined): ContinuationCompactionInstructions {
	if (customInstructions === undefined) return { nonce: undefined, instructions: undefined };
	let nonce: string | undefined;
	const kept: string[] = [];
	for (const line of customInstructions.split("\n")) {
		const match = COMPACTION_REQUEST_MARKER_PATTERN.exec(line.trim());
		if (match) {
			nonce = match[1];
			continue;
		}
		kept.push(line);
	}
	const instructions = kept.join("\n").trim();
	return { nonce, instructions: instructions.length > 0 ? instructions : undefined };
}

/**
 * Claim ownership of the compaction Pi is starting, consuming the one-shot request this
 * package registered. A compaction that does not carry that request's marker is Pi's or the
 * user's, so the request is left pending for the compaction it was registered for.
 */
export function claimContinuationCompactionRequest(runtime: ContinuationRuntimeState, requestNonce?: string): string | undefined {
	const request = runtime.pendingCompactionRequest;
	if (!request || requestNonce !== request.nonce) return undefined;
	runtime.pendingCompactionRequest = undefined;
	return isActiveRunningContinuationEvent(runtime, request.eventId) ? request.eventId : undefined;
}

/** Return the runtime-local latest event rendered by /continue status. */
export function getLatestContinuationEvent(runtime: ContinuationRuntimeState): ContinuationLatestEvent | undefined {
	return runtime.latestEvent;
}

export function getLatestContinuationLedger(runtime: ContinuationRuntimeState): ContinuationLedgerSnapshot | undefined {
	return runtime.latestLedger;
}

export function describeGuardTrigger(trigger: MidRunGuardTrigger): string {
	return `${trigger.estimatedTokens.toLocaleString()}/${trigger.contextWindow.toLocaleString()} tokens, threshold ${trigger.thresholdTokens.toLocaleString()}`;
}

export function buildGuardFailureKey(trigger: MidRunGuardTrigger): string {
	return [
		trigger.contextWindow,
		trigger.reserveTokens,
		trigger.thresholdTokens,
		trigger.estimatedTokens,
		trigger.usageTokens,
		trigger.trailingTokens,
		trigger.lastUsageIndex ?? "none",
	].join(":");
}

export function buildGuardInstructions(trigger: MidRunGuardTrigger): string {
	return [
		"Automatic mid-run continuation triggered after a completed assistant/tool-result batch, before Pi sent another model request.",
		`Estimated context: ${trigger.estimatedTokens} tokens.`,
		`Compaction threshold: ${trigger.thresholdTokens} tokens (${trigger.contextWindow} context window - ${trigger.reserveTokens} reserve).`,
		"Prioritize current state, latest tool results, remaining task intent, file changes, blockers, and exact next steps.",
	].join("\n");
}

function sourceLabel(source: ContinuationRequestSource): string {
	if (source === "command-queue") return "queued /continue";
	if (source === "command-steer") return "/continue steer";
	return "automatic continuation";
}

// Pi's TUI empties the message queue into the editor draft when an extension aborts, so a
// queued follow-up silently stops being sent and the user has to be told where it went.
function abortActiveTurn(ctx: ExtensionContext): void {
	const hadQueuedMessages = typeof ctx.hasPendingMessages === "function" ? ctx.hasPendingMessages() : undefined;
	ctx.abort();
	if (hadQueuedMessages === false) return;
	if (hadQueuedMessages) {
		notify(ctx, QUEUED_MESSAGES_MOVED_WARNING, "warning");
		return;
	}
	warnInputOnce(ctx, "abort-restored-queue", QUEUED_MESSAGES_MOVED_WARNING);
}

function chainBudgetRefusal(runtime: ContinuationRuntimeState, limits: ContinuationChainLimits | undefined): string | undefined {
	if (!limits) return undefined;
	if (limits.maxChainedContinuations > 0 && runtime.chainedContinuationCount >= limits.maxChainedContinuations) {
		return `${runtime.chainedContinuationCount} automatic continuations already ran without new input (maxChainedContinuations ${limits.maxChainedContinuations}).`;
	}
	if (limits.maxChainedSynthesisCostUsd > 0 && runtime.chainedSynthesisCostUsd >= limits.maxChainedSynthesisCostUsd) {
		return `chained automatic continuations already spent $${runtime.chainedSynthesisCostUsd.toFixed(4)} on handoff synthesis (maxChainedSynthesisCostUsd ${limits.maxChainedSynthesisCostUsd}).`;
	}
	return undefined;
}

/** Add paid handoff synthesis to the automatic-continuation chain budget. */
export function recordContinuationSynthesisSpend(runtime: ContinuationRuntimeState, costUsd: number | undefined): void {
	if (costUsd === undefined || !Number.isFinite(costUsd) || costUsd <= 0) return;
	runtime.chainedSynthesisCostUsd += costUsd;
}

/** Clear the automatic-continuation chain budget once new operator input arrives. */
export function resetContinuationChainBudget(runtime: ContinuationRuntimeState): void {
	runtime.chainedContinuationCount = 0;
	runtime.chainedSynthesisCostUsd = 0;
}

function isAwaitingResumeEventCurrent(runtime: ContinuationRuntimeState): boolean {
	const eventId = runtime.awaitingResumeEventId;
	return eventId !== undefined
		&& runtime.activeEventId === eventId
		&& runtime.latestEvent?.id === eventId
		&& runtime.latestEvent.status === "running";
}

export function clearStaleAwaitingContinuationResume(runtime: ContinuationRuntimeState): void {
	if (runtime.awaitingResumeEventId && !isAwaitingResumeEventCurrent(runtime)) {
		runtime.awaitingResumeEventId = undefined;
		clearResumeStartTimeout(runtime);
	}
	if (runtime.pendingResumeDispatch && runtime.pendingResumeDispatch.eventId !== runtime.activeEventId) {
		clearPendingResumeDispatch(runtime);
	}
}

function hasActiveContinuationSettlement(runtime: ContinuationRuntimeState): boolean {
	clearStaleAwaitingContinuationResume(runtime);
	return runtime.activeEventId !== undefined || runtime.awaitingResumeEventId !== undefined;
}

function finishRunningResumeForChainedContinuation(runtime: ContinuationRuntimeState): boolean {
	clearStaleAwaitingContinuationResume(runtime);
	const eventId = runtime.awaitingResumeEventId;
	if (!eventId || runtime.activeEventId !== eventId || runtime.latestEvent?.id !== eventId) return false;
	if (runtime.latestEvent.resume.status !== "running") return false;
	if (!settleContinuationResume(runtime, eventId, "completed", { stopReason: CHAINED_CONTINUATION_STOP_REASON })) return false;
	clearResumeStartTimeout(runtime);
	runtime.awaitingResumeEventId = undefined;
	return true;
}

function compactionFailureReason(runtime: ContinuationRuntimeState, eventId: string): string {
	const event = runtime.latestEvent;
	if (event?.id === eventId && event.artifactStatus === "aborted" && event.failureReason) return event.failureReason;
	return COMPACTION_FAILURE;
}

/** Start the package-owned compaction pipeline once, with visible lifecycle settlement. */
export function startContinuationCompaction(
	ctx: ExtensionContext,
	runtime: ContinuationRuntimeState,
	options: StartContinuationCompactionOptions,
): boolean {
	clearStaleAwaitingContinuationResume(runtime);
	if (runtime.compactionRunning) {
		if (options.abortActiveRun && options.source === "mid-run-guard") abortActiveTurn(ctx);
		notify(ctx, "A continuation handoff is already being saved.", "warning");
		return false;
	}
	if (options.source === "mid-run-guard") {
		finishRunningResumeForChainedContinuation(runtime);
	}
	if (hasActiveContinuationSettlement(runtime)) {
		if (options.source === "mid-run-guard" && options.abortActiveRun) abortActiveTurn(ctx);
		notify(ctx, "The previous continuation is still resuming; no new handoff was started.", "warning");
		return false;
	}
	const guardKey = options.trigger ? buildGuardFailureKey(options.trigger) : undefined;
	if (options.source === "mid-run-guard" && guardKey && runtime.guardFailureKey === guardKey) {
		abortActiveTurn(ctx);
		recordBlockedContinuationEvent(
			runtime,
			options.source,
			options.trigger,
			BLOCKED_RETRY_FAILURE,
		);
		notify(ctx, "pi-continue paused before another over-limit model request. Review /continue status before retrying.", "error");
		return false;
	}
	const chainRefusal = options.source === "mid-run-guard" ? chainBudgetRefusal(runtime, options.chainLimits) : undefined;
	if (chainRefusal) {
		abortActiveTurn(ctx);
		recordBlockedContinuationEvent(
			runtime,
			options.source,
			options.trigger,
			`Automatic continuation stopped by the chain budget: ${chainRefusal}`,
		);
		notify(
			ctx,
			`pi-continue stopped automatic continuation: ${chainRefusal} Send a message or run /continue to resume, or raise the limit in /continue settings.`,
			"error",
		);
		return false;
	}
	runtime.compactionRunning = true;
	const event = beginContinuationEvent(
		runtime,
		options.source,
		options.trigger,
		options.continueAfterComplete ? "pending" : "not-requested",
	);
	if (options.source === "mid-run-guard") runtime.chainedContinuationCount += 1;
	beginWorkingVisuals(ctx, runtime, event.id, "pi-continue saving handoff");
	if (options.abortActiveRun) abortActiveTurn(ctx);
	const label = sourceLabel(options.source);
	const triggerText = options.trigger ? ` (${describeGuardTrigger(options.trigger)})` : "";
	notify(ctx, `${label}: saving handoff${triggerText}.`, "info");
	const requestNonce = randomUUID();
	const customInstructions = buildContinuationCompactionInstructions(
		mergeInstructions([
			options.instructions,
			options.trigger ? buildGuardInstructions(options.trigger) : undefined,
		]),
		requestNonce,
	);
	let compactionCallbackSettled = false;
	function claimCompactionCallback(): boolean {
		if (compactionCallbackSettled) return false;
		compactionCallbackSettled = true;
		return isActiveRunningContinuationEvent(runtime, event.id);
	}
	if (options.continueAfterComplete) {
		preparePendingResumeDispatch(runtime, {
			eventId: event.id,
			label,
			sendContinuation: options.sendContinuation,
			onContinuationFailed: options.onContinuationFailed,
			resumeStartTimeoutMs: options.resumeStartTimeoutMs ?? RESUME_START_TIMEOUT_MS,
			compactionProofTimeoutMs: options.compactionProofTimeoutMs ?? RESUME_START_TIMEOUT_MS,
			failureGuardKey: guardKey,
		});
	}
	function failCompaction(reason: string): void {
		runtime.compactionRunning = false;
		runtime.pendingCompactionRequest = undefined;
		if (guardKey) runtime.guardFailureKey = guardKey;
		options.onContinuationFailed?.(event.id);
		finishContinuationEvent(runtime, event.id, "failed", reason);
		clearPendingResumeDispatch(runtime);
		clearResumeStartTimeout(runtime);
		runtime.awaitingResumeEventId = undefined;
		settleWorkingVisuals(ctx, runtime, event.id);
		notify(ctx, `${label}: handoff failed: ${reason}`, "error");
	}
	// Registered as late as possible, immediately before the request it correlates with.
	runtime.pendingCompactionRequest = { eventId: event.id, nonce: requestNonce };
	try {
		ctx.compact({
			customInstructions,
			onComplete: () => {
				if (!claimCompactionCallback()) return;
				runtime.compactionRunning = false;
				runtime.guardFailureKey = undefined;
				if (options.continueAfterComplete) {
					markContinuationCompactionComplete(ctx, runtime, event.id);
					return;
				}
				finishContinuationEvent(runtime, event.id, "completed", undefined);
				settleWorkingVisuals(ctx, runtime, event.id);
				notify(ctx, `${label}: handoff saved.`, "info");
			},
			onError: () => {
				if (!claimCompactionCallback()) return;
				failCompaction(compactionFailureReason(runtime, event.id));
			},
		});
	} catch {
		failCompaction(compactionFailureReason(runtime, event.id));
		return false;
	}
	return true;
}

export function markAwaitingContinuationResumeStarted(runtime: ContinuationRuntimeState): string | undefined {
	clearStaleAwaitingContinuationResume(runtime);
	const eventId = runtime.awaitingResumeEventId;
	if (!eventId) return undefined;
	if (!markContinuationResumeStarted(runtime, eventId)) return undefined;
	clearResumeStartTimeout(runtime);
	return eventId;
}

function requestedAssistantModel(message: AssistantMessage): string {
	return `${message.provider}/${message.model}`;
}

export function settleAwaitingContinuationResumeFromAssistant(
	runtime: ContinuationRuntimeState,
	message: AssistantMessage,
): ContinuationResumeSettlement | undefined {
	clearStaleAwaitingContinuationResume(runtime);
	const eventId = runtime.awaitingResumeEventId;
	if (!eventId || runtime.latestEvent?.id !== eventId || runtime.latestEvent.resume.status !== "running") return undefined;
	if (message.stopReason === "toolUse") return undefined;
	if (message.stopReason === "stop") {
		if (settleContinuationResume(runtime, eventId, "completed", {
			stopReason: message.stopReason,
			requestedModel: requestedAssistantModel(message),
			responseModel: message.responseModel,
		})) {
			clearResumeStartTimeout(runtime);
			runtime.awaitingResumeEventId = undefined;
			return { eventId, status: "completed" };
		}
		return undefined;
	}
	if (message.stopReason === "aborted") {
		if (settleContinuationResume(runtime, eventId, "aborted", {
			stopReason: message.stopReason,
			requestedModel: requestedAssistantModel(message),
			responseModel: message.responseModel,
			failureReason: RESUME_ABORTED_FAILURE,
		})) {
			clearResumeStartTimeout(runtime);
			runtime.awaitingResumeEventId = undefined;
			return { eventId, status: "aborted" };
		}
		return undefined;
	}
	const reason = message.stopReason === "length"
		? RESUME_LIMIT_FAILURE
		: RESUME_NO_ASSISTANT_FAILURE;
	if (settleContinuationResume(runtime, eventId, "failed", {
		stopReason: message.stopReason,
		requestedModel: requestedAssistantModel(message),
		responseModel: message.responseModel,
		failureReason: reason,
	})) {
		clearResumeStartTimeout(runtime);
		runtime.awaitingResumeEventId = undefined;
		return { eventId, status: "failed" };
	}
	return undefined;
}

export function failAwaitingContinuationResume(runtime: ContinuationRuntimeState, reason: string): string | undefined {
	clearStaleAwaitingContinuationResume(runtime);
	const eventId = runtime.awaitingResumeEventId;
	if (!eventId) return undefined;
	if (!settleContinuationResume(runtime, eventId, "failed", { failureReason: reason })) return undefined;
	clearResumeStartTimeout(runtime);
	runtime.awaitingResumeEventId = undefined;
	return eventId;
}

export function failRunningAwaitingContinuationResume(
	runtime: ContinuationRuntimeState,
	reason: string,
): ContinuationResumeSettlement | undefined {
	clearStaleAwaitingContinuationResume(runtime);
	const eventId = runtime.awaitingResumeEventId;
	if (!eventId || runtime.latestEvent?.id !== eventId || runtime.latestEvent.resume.status !== "running") return undefined;
	if (!settleContinuationResume(runtime, eventId, "failed", { failureReason: reason })) return undefined;
	clearResumeStartTimeout(runtime);
	runtime.awaitingResumeEventId = undefined;
	return { eventId, status: "failed" };
}

/** Execute /continue in immediate steer mode or wait-until-idle queue mode. */
export async function runContinuationCommand(
	ctx: ExtensionCommandContext,
	runtime: ContinuationRuntimeState,
	args: string | undefined,
	sendContinuation: (prompt: string) => void | Promise<void>,
	onContinuationFailed?: (eventId: string) => void,
): Promise<void> {
	const request = parseContinuationRequest(args);
	resetContinuationChainBudget(runtime);
	if (request.mode === "queue") {
		notify(ctx, "Queued continuation for the next idle point.", "info");
		await ctx.waitForIdle();
		startContinuationCompaction(ctx, runtime, {
			source: "command-queue",
			instructions: request.instructions,
			trigger: undefined,
			abortActiveRun: false,
			continueAfterComplete: true,
			sendContinuation,
			onContinuationFailed,
		});
		return;
	}
	startContinuationCompaction(ctx, runtime, {
		source: "command-steer",
		instructions: request.instructions,
		trigger: undefined,
		abortActiveRun: !ctx.isIdle(),
		continueAfterComplete: true,
		sendContinuation,
		onContinuationFailed,
	});
}
