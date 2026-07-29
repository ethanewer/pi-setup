import { randomUUID } from "node:crypto";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { loadHistoryPromptAssets } from "./src/assets.ts";
import { parseHistoryArtifacts } from "./src/blocks.ts";
import { splitContinueSubcommand, shouldOpenContinuePalette } from "./src/command-shape.ts";
import { runContinuePaletteResult, runEnabledContinuationCommand } from "./src/command-runner.ts";
import { runLedgerCommand, runPreviewCommand, runResetCommand, runSettingsDialog, runStatusCommand } from "./src/commands.ts";
import { getContinueArgumentCompletions } from "./src/completions.ts";
import { normalizeCompactionPreparation, resolveKeptEntryBoundary, snapshotFileOperations, stripCompactionPreparationMessages } from "./src/compaction-preparation.ts";
import { composeCompactionSummary } from "./src/compose.ts";
import { DEFAULT_CONTINUE_CONFIG, loadContinuationConfig } from "./src/config.ts";
import {
	abandonActiveContinuationEvent,
	failPendingOutputWritesForEvent,
	getActiveContinuationEventId,
	isActiveRunningContinuationEvent,
	isLatestContinuationEvent,
	markContinuationArtifact,
	planContinuationOutputWrites,
	recordContinuationSynthesisFailure,
	recordContinuationSynthesisTelemetry,
	recordOutputWriteResult,
} from "./src/continuation-event.ts";
import { buildContinuationDetails, buildContinuationSynthesisTelemetry, parseContinuationDetails } from "./src/details.ts";
import { SYNTHESIS_ABORT_MESSAGE } from "./src/synthesis-error.ts";
import { warnInputOnce } from "./src/input-warnings.ts";
import { buildLedgerSnapshot, createContinuationLedgerOverlayController } from "./src/ledger-viewer.ts";
import { runMidRunGuard } from "./src/mid-run-guard.ts";
import { PromptPassError, runPromptPass } from "./src/model.ts";
import { loadPiInternals } from "./src/pi-internals.ts";
import { compileHistoryPrompt } from "./src/prompt.ts";
import { ensureContinuationArtifactIgnored, MarkdownWriteRefusedError, resolveProjectContext, writeNormalizedMarkdownFile } from "./src/project.ts";
import { isProjectScopeTrusted } from "./src/project-trust.ts";
import { isContinuationPromptText, isContinuationPromptUserMessage } from "./src/prompt-dispatch.ts";
import { showContinuePalette } from "./src/palette.ts";
import {
	CONTINUATION_PROMPT,
	armDeferredResumeStartTimeout,
	claimContinuationCompactionRequest,
	clearResumeStartTimeout,
	createContinuationRuntimeState,
	dispatchVerifiedContinuationResume,
	failContinuationCompactionProof,
	failRunningAwaitingContinuationResume,
	markAwaitingContinuationResumeStarted,
	parseContinuationCompactionInstructions,
	recordContinuationSynthesisSpend,
	resetContinuationChainBudget,
	settleAwaitingContinuationResumeFromAssistant,
	type ContinuationRuntimeState,
	verifyContinuationCompactionProof,
} from "./src/runtime.ts";
import {
	INVALID_COMPACTION_PROOF_FAILURE,
	NATIVE_COMPACTION_FALLBACK_FAILURE,
	clearPendingResumeDispatch,
} from "./src/resume-proof.ts";
import type { AgentGuideWriteStatus, ContinuationSynthesisFailure, ContinuationSynthesisTelemetry, ParsedHistoryArtifacts, PendingOutputWrite, WriteMode } from "./src/types.ts";
import {
	clearWorkingVisuals,
	settleWorkingVisuals,
	updateWorkingVisuals,
} from "./src/working-ui.ts";

function decideAgentGuideWriteStatus(writeMode: WriteMode, agentGuideMd: string | undefined): AgentGuideWriteStatus {
	if (writeMode === "off") return "write-off";
	return agentGuideMd ? "replacement-pending" : "no-replacement";
}

// Pi hands the same event object to every handler, so replacing the instructions in place is what
// keeps the correlation marker out of whatever summarizes this compaction next.
function stripRequestMarkerFromEvent(event: { customInstructions?: string }, instructions: string | undefined): void {
	try {
		event.customInstructions = instructions;
	} catch {
		// A host that hands out a frozen event keeps its own copy; the marker is inert either way.
	}
}

function isAssistantMessage(message: unknown): message is AssistantMessage {
	return typeof message === "object" && message !== null && "role" in message && message.role === "assistant";
}

function isUserMessage(message: unknown): boolean {
	return typeof message === "object" && message !== null && "role" in message && message.role === "user";
}

const OUTPUT_WRITE_FAILURE = "Output write failed; check the configured path and permissions.";
const PENDING_OUTPUT_WRITE_FAILURE = "Output write did not complete before continuation failed.";
const MID_RUN_GUARD_FAILURE = "pi-continue could not evaluate the automatic continuation guard for this request; the context threshold is unguarded until it recovers.";
const SYNTHESIS_NATIVE_FALLBACK = "pi-continue could not synthesize a handoff brief; Pi saved its own compaction instead.";
const INTERNALS_NATIVE_FALLBACK = "pi-continue could not read Pi's internal compaction helpers; Pi saved its own compaction instead.";
const INTERNALS_UNAVAILABLE_FAILURE = "Pi internal compaction helpers were unavailable for this handoff.";
const KEPT_BOUNDARY_FALLBACK = "pi-continue could not re-check which entries Pi keeps after this handoff and used the boundary Pi prepared before synthesis.";
const FOREIGN_COMPACTION_WARNING = "pi-continue left this compaction to Pi because it did not carry the handoff request pi-continue registered; the requested handoff is still waiting for its own compaction.";
const HEADLESS_OVERWRITE_REFUSAL = "pi-continue kept existing agent-guide content it did not write because a non-interactive session cannot ask; set agentGuideOverwritePolicy to \"allow\" in the global pi-continue config to replace it unprompted.";
const OUTSIDE_PROJECT_OPT_IN_HINT = "Set agentGuideAllowOutsideProject to true in the global pi-continue config to allow a guide whose real path leaves the project.";
const SYMLINKED_ANCESTOR_OPT_IN_HINT = "If a parent directory on that path is a symlink you created on purpose, set allowSymlinkedOutputDirectory to true in the global pi-continue config.";
const RESERVED_PATH_HINT = "Choose an output path that stays out of repo-owned machinery; no setting opens that location.";
const REDIRECTED_FILE_HINT = "A symlink at the output path itself is never followed and no setting waives that; replace it with a real file, or point the configured path at the real file.";
const AGENT_GUIDE_READ_HINT = `The handoff was synthesized without it. ${OUTSIDE_PROJECT_OPT_IN_HINT}`;
// A confirmation asked while the resumed turn is running would sit on the resume's critical path,
// so the deferred write waits for settlement and this backstop keeps it reachable regardless.
const DEFERRED_WRITE_BACKSTOP_MS = 300_000;

// The hint has to name a setting that would actually change the outcome for this target, so a
// reserved path is never reported as something an outside-project opt-in could unlock.
function outputWriteFailureReason(error: unknown, target: PendingOutputWrite["target"]): string {
	if (!(error instanceof MarkdownWriteRefusedError)) return OUTPUT_WRITE_FAILURE;
	if (error.reason === "reserved-path") return `${error.message} ${RESERVED_PATH_HINT}`;
	if (error.reason === "redirected-file") return `${error.message} ${REDIRECTED_FILE_HINT}`;
	if (error.reason === "redirected-path") return `${error.message} ${SYMLINKED_ANCESTOR_OPT_IN_HINT}`;
	if (error.reason === "outside-project") {
		return `${error.message} ${target === "agent-guide" ? OUTSIDE_PROJECT_OPT_IN_HINT : SYMLINKED_ANCESTOR_OPT_IN_HINT}`;
	}
	return error.message;
}

async function confirmOutputOverwrite(ctx: ExtensionContext, label: string, path: string): Promise<boolean> {
	// Only a target that exists, differs, and was not written by this package reaches here, so a
	// non-interactive session refuses just the writes that would clobber someone else's content.
	if (!ctx.hasUI) {
		warnInputOnce(ctx, "headless-overwrite", HEADLESS_OVERWRITE_REFUSAL);
		return false;
	}
	return ctx.ui.confirm(
		`Replace ${label}?`,
		`pi-continue wants to replace ${path} with a model-authored full replacement. Set agentGuideOverwritePolicy to "allow" to skip this prompt.`,
	);
}

class ArtifactParseError extends Error {
	readonly failure: ContinuationSynthesisFailure;

	constructor(failure: ContinuationSynthesisFailure) {
		super(failure.code);
		this.failure = failure;
	}
}

function normalizeSynthesisFailure(error: unknown): ContinuationSynthesisFailure {
	if (error instanceof PromptPassError) {
		return {
			kind: "model-provider-call",
			code: error.code,
			pass: "history",
			requestedModel: error.requestedModel,
			httpStatus: error.httpStatus,
		};
	}
	if (error instanceof ArtifactParseError) return error.failure;
	return { kind: "internal", code: "internal-error", pass: "history" };
}

export default function (pi: ExtensionAPI) {
	const pendingOutputWrites = new Map<string, PendingOutputWrite>();
	const resumeSettlementWaiters = new Set<{ eventId: string; release: () => void }>();
	const runtime = createContinuationRuntimeState();
	const ledgerOverlay = createContinuationLedgerOverlayController();
	let shuttingDown = false;

	function releaseResumeSettlementWaiters(eventId: string | undefined): void {
		for (const waiter of resumeSettlementWaiters) {
			if (eventId !== undefined && waiter.eventId !== eventId) continue;
			resumeSettlementWaiters.delete(waiter);
			waiter.release();
		}
	}

	// Wait for the resumed turn to settle before doing work that can block on the operator.
	function whenResumeSettled(eventId: string): Promise<void> {
		if (!isActiveRunningContinuationEvent(runtime, eventId)) return Promise.resolve();
		return new Promise<void>((resolve) => {
			const timer = setTimeout(() => {
				resumeSettlementWaiters.delete(waiter);
				resolve();
			}, DEFERRED_WRITE_BACKSTOP_MS);
			timer.unref?.();
			const release = (): void => {
				clearTimeout(timer);
				resolve();
			};
			const waiter = { eventId, release };
			resumeSettlementWaiters.add(waiter);
		});
	}

	function cleanupPendingOutputWrites(eventId: string): void {
		releaseResumeSettlementWaiters(eventId);
		let removed = false;
		for (const [writeId, pending] of pendingOutputWrites) {
			if (pending.eventId !== eventId) continue;
			pendingOutputWrites.delete(writeId);
			removed = true;
		}
		if (removed) {
			failPendingOutputWritesForEvent(runtime, eventId, PENDING_OUTPUT_WRITE_FAILURE);
		}
	}

	// A deferred write may no longer be able to ask the operator, but it is never dropped in
	// silence: the write is still attempted, and a replacement that would clobber content this
	// package did not write is refused with a reason that says what to do about it.
	function describeUnaskableDeferral(eventId: string): string | undefined {
		if (shuttingDown) return "the Pi session shut down before the confirmation could be asked";
		if (!isLatestContinuationEvent(runtime, eventId)) return "a newer continuation replaced this one before the confirmation could be asked";
		return undefined;
	}

	function refuseUnaskableOverwrite(ctx: ExtensionContext, pending: PendingOutputWrite, path: string, deferral: string): boolean {
		warnInputOnce(
			ctx,
			`unaskable-overwrite:${pending.eventId}:${pending.target}`,
			`pi-continue kept the existing ${path} because ${deferral}; the ${pending.label} it synthesized was not written. Run /continue again to write it, or set agentGuideOverwritePolicy to "allow" in the global pi-continue config.`,
		);
		return false;
	}

	// Output writes run off the resume path: the resume was already dispatched, and neither a slow
	// disk nor a confirmation the operator has not answered yet may fail the handoff.
	async function runPendingOutputWrites(ctx: ExtensionContext, writes: PendingOutputWrite[]): Promise<void> {
		for (const pending of writes) {
			if (pending.confirmOverwrite) await whenResumeSettled(pending.eventId);
			const deferral = describeUnaskableDeferral(pending.eventId);
			try {
				if (pending.target === "continuation-artifact") {
					await ensureContinuationArtifactIgnored(pending.projectRoot, pending.allowSymlinkedAncestor);
				}
				const result = await writeNormalizedMarkdownFile(pending.path, pending.content, {
					containmentRoot: pending.projectRoot,
					// Both output paths are package-owned, so a symlink planted at one of them redirects a
					// model-authored full replacement onto a file nobody chose. Only the operator's own
					// global opt-in makes a symlinked guide a supported layout.
					refuseRedirectedPath: !pending.allowOutsideRoot,
					allowOutsideRoot: pending.allowOutsideRoot,
					allowSymlinkedAncestor: pending.allowSymlinkedAncestor,
					// The guide is the target that can require approval, so its provenance is recorded
					// whichever overwrite policy is in force.
					trackProvenance: pending.target === "agent-guide",
					confirmOverwrite: pending.confirmOverwrite
						? (path) => deferral === undefined
							? confirmOutputOverwrite(ctx, pending.label, path)
							: Promise.resolve(refuseUnaskableOverwrite(ctx, pending, path, deferral))
						: undefined,
				});
				recordOutputWriteResult(runtime, pending.eventId, pending.target, result, undefined);
				if (ctx.hasUI) {
					ctx.ui.notify(
						result === "updated"
							? `Updated ${pending.label}.`
							: `${pending.label} was already up to date.`,
						"info",
					);
				}
			} catch (error) {
				const reason = outputWriteFailureReason(error, pending.target);
				recordOutputWriteResult(runtime, pending.eventId, pending.target, "failed", reason);
				// Queued rather than notified directly: a write that finishes after the UI is gone still
				// has to report itself, and the ledger carries the same reason either way.
				warnInputOnce(ctx, `output-write:${pending.eventId}:${pending.target}`, `Could not update ${pending.label}: ${reason}`);
			}
		}
	}

	pi.registerCommand("continue", {
		description: "Save a same-session handoff, resume this run, or inspect continuation settings.",
		getArgumentCompletions: getContinueArgumentCompletions,
		handler: async (args, ctx) => {
			if (shouldOpenContinuePalette(args, ctx.hasUI)) {
				const palette = await showContinuePalette(pi, ctx, runtime);
				if (palette.supported) {
					if (palette.result) {
						await runContinuePaletteResult(pi, ctx, runtime, ledgerOverlay, palette.result, (eventId) => cleanupPendingOutputWrites(eventId));
					}
					return;
				}
			}
			const subcommand = splitContinueSubcommand(args);
			if (subcommand?.name === "status") {
				await runStatusCommand(pi, ctx, runtime);
				return;
			}
			if (subcommand?.name === "ledger") {
				await runLedgerCommand(ctx, runtime, ledgerOverlay);
				return;
			}
			if (subcommand?.name === "settings") {
				await runSettingsDialog(pi, ctx, subcommand.rest);
				return;
			}
			if (subcommand?.name === "reset") {
				await runResetCommand(pi, ctx, subcommand.rest);
				return;
			}
			if (subcommand?.name === "preview") {
				await runPreviewCommand(pi, ctx, subcommand.rest);
				return;
			}
			await runEnabledContinuationCommand(
				pi,
				ctx,
				runtime,
				args,
				(eventId) => cleanupPendingOutputWrites(eventId),
			);
		},
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!isContinuationPromptText(event.prompt, CONTINUATION_PROMPT)) return;
		const eventId = markAwaitingContinuationResumeStarted(runtime);
		if (!eventId) return;
		updateWorkingVisuals(ctx, runtime, eventId, "pi-continue resume running");
	});

	pi.on("message_start", async (event, ctx) => {
		if (isContinuationPromptUserMessage(event.message, CONTINUATION_PROMPT)) {
			const eventId = markAwaitingContinuationResumeStarted(runtime);
			if (eventId) {
				updateWorkingVisuals(ctx, runtime, eventId, "pi-continue resume running");
			}
			return;
		}
		// Anything the user sends themselves ends the automatic-continuation chain.
		if (isUserMessage(event.message)) resetContinuationChainBudget(runtime);
		if (!isAssistantMessage(event.message)) return;
		const eventId = runtime.awaitingResumeEventId;
		if (!eventId || runtime.latestEvent?.id !== eventId || runtime.latestEvent.resume.status !== "running") return;
		updateWorkingVisuals(ctx, runtime, eventId, "pi-continue resume running");
	});

	pi.on("agent_end", async (_event, ctx) => {
		const settlement = failRunningAwaitingContinuationResume(runtime, "Continuation resume did not produce an assistant response.");
		if (settlement) {
			settleWorkingVisuals(ctx, runtime, settlement.eventId);
			releaseResumeSettlementWaiters(settlement.eventId);
			return;
		}
		armDeferredResumeStartTimeout(ctx, runtime);
	});

	pi.on("message_end", async (event, ctx) => {
		if (!isAssistantMessage(event.message)) return;
		const settlement = settleAwaitingContinuationResumeFromAssistant(runtime, event.message);
		if (!settlement) return;
		settleWorkingVisuals(ctx, runtime, settlement.eventId);
		releaseResumeSettlementWaiters(settlement.eventId);
	});

	pi.on("context", async (event, ctx) => {
		// The guard runs on every provider request, so a failure here must degrade to
		// "unguarded" with one warning instead of erroring out each request.
		try {
			await runMidRunGuard(pi, ctx, runtime, event.messages, (eventId) => cleanupPendingOutputWrites(eventId));
		} catch {
			warnInputOnce(ctx, "mid-run-guard", MID_RUN_GUARD_FAILURE);
		}
	});

	pi.on("session_before_compact", async (event, ctx) => {
		const sessionId = ctx.sessionManager.getSessionId();
		// Only the compaction this package asked Pi to run is ours; it is recognized by the one-shot
		// marker on its custom instructions, so a manual /compact or an automatic Pi compaction that
		// merely overlaps an active event stays with Pi.
		const requested = parseContinuationCompactionInstructions(event.customInstructions);
		const ownerEventId = claimContinuationCompactionRequest(runtime, requested.nonce);
		if (ownerEventId === undefined) {
			// A surviving request means this compaction was somebody else's while ours was pending.
			if (runtime.pendingCompactionRequest) warnInputOnce(ctx, "foreign-compaction", FOREIGN_COMPACTION_WARNING);
			return undefined;
		}
		// The marker is this package's private correlation token, not an instruction. Strip it from
		// the event itself so every later reader - Pi's own summarizer on the fallback path, and any
		// other extension on this event - sees only the operator's instructions.
		stripRequestMarkerFromEvent(event, requested.instructions);
		const ownerStillActive = () => isActiveRunningContinuationEvent(runtime, ownerEventId);
		const ownerLostResult = () => ownerStillActive() ? undefined : { cancel: true as const };
		const projectContext = await resolveProjectContext(pi, ctx.cwd, sessionId);
		const ownerLostAfterProjectContext = ownerLostResult();
		if (ownerLostAfterProjectContext) return ownerLostAfterProjectContext;
		const projectTrusted = isProjectScopeTrusted(ctx, projectContext.projectRoot);
		const config = loadContinuationConfig(projectContext.projectRoot, projectTrusted);
		if (!config.enabled) return { cancel: true };
		const resolvedProjectContext = await resolveProjectContext(
			pi,
			ctx.cwd,
			sessionId,
			config.agentGuidePath,
			config.agentGuideAllowOutsideProject,
		);
		const ownerLostAfterResolvedContext = ownerLostResult();
		if (ownerLostAfterResolvedContext) return ownerLostAfterResolvedContext;
		// A guide that exists but was not read would otherwise look like a repo with no guide at all,
		// and the summarizer would be asked to write one from scratch.
		if (resolvedProjectContext.agentGuideReadRefusal) {
			warnInputOnce(
				ctx,
				`agent-guide-read:${resolvedProjectContext.agentGuidePath}`,
				`${resolvedProjectContext.agentGuideReadRefusal} ${AGENT_GUIDE_READ_HINT}`,
			);
		}
		const normalizedPreparation = normalizeCompactionPreparation(event.preparation, event.branchEntries);
		if (normalizedPreparation.repairedProviderUnsafeSuffix && ctx.hasUI) {
			ctx.ui.notify("pi-continue summarized a provider-unsafe kept suffix before resuming.", "warning");
		} else if (normalizedPreparation.repairedNoOpCut && ctx.hasUI) {
			ctx.ui.notify("pi-continue moved the handoff to a safer checkpoint before resuming.", "warning");
		}
		// Strip pi-continue's own receiver prompt so the synthesizer never mistakes
		// our resume wrapper ("Continue from the same-session pi-continue/v4 handoff…")
		// for user content. Otherwise the synthesizer can promote our wrapper sentences
		// as `forbid` or `task` entries.
		const preparation = stripCompactionPreparationMessages(normalizedPreparation, (message) =>
			isContinuationPromptUserMessage(message, CONTINUATION_PROMPT)
		);
		const fileOpsSnapshot = snapshotFileOperations(preparation.fileOps);
		let internals: Awaited<ReturnType<typeof loadPiInternals>>;
		try {
			internals = await loadPiInternals();
		} catch {
			if (ownerStillActive()) {
				markContinuationArtifact(runtime, ownerEventId, "aborted", INTERNALS_UNAVAILABLE_FAILURE);
			}
			if (ctx.hasUI) ctx.ui.notify(INTERNALS_NATIVE_FALLBACK, "warning");
			return undefined;
		}
		const ownerLostAfterInternals = ownerLostResult();
		if (ownerLostAfterInternals) return ownerLostAfterInternals;
		const messagesToSummarize = preparation.messagesToSummarize;
		const turnPrefixMessages = preparation.turnPrefixMessages;
		const turnPrefixTranscript = preparation.isSplitTurn && turnPrefixMessages.length > 0
			? internals.serializeConversation(internals.convertToLlm(turnPrefixMessages))
			: undefined;
		const historyPrompt = compileHistoryPrompt(
			loadHistoryPromptAssets(
				resolvedProjectContext.projectRoot,
				config.promptOverridePolicy,
				preparation.previousSummary ? "update" : "initial",
				projectTrusted,
			),
			{
				scenario: preparation.previousSummary ? "update" : "initial",
				projectRoot: resolvedProjectContext.projectRoot,
				agentGuidePath: resolvedProjectContext.agentGuidePath,
				existingAgentGuide: resolvedProjectContext.existingAgentGuide,
				previousSummary: preparation.previousSummary,
				historyTranscript: internals.serializeConversation(internals.convertToLlm(messagesToSummarize)),
				turnPrefixTranscript,
				customInstructions: requested.instructions,
				fileOps: fileOpsSnapshot,
			},
		);
		let historyArtifacts: ParsedHistoryArtifacts;
		let synthesis: ContinuationSynthesisTelemetry | undefined;
		try {
			const historyOutput = await runPromptPass(pi, ctx, config, historyPrompt, preparation.settings.reserveTokens, event.signal);
			const ownerLostAfterSynthesis = ownerLostResult();
			if (ownerLostAfterSynthesis) return ownerLostAfterSynthesis;
			synthesis = buildContinuationSynthesisTelemetry(historyOutput);
			recordContinuationSynthesisSpend(runtime, synthesis?.totalCost);
			recordContinuationSynthesisTelemetry(runtime, ownerEventId, synthesis);
			const parsedHistoryArtifacts = parseHistoryArtifacts(historyOutput.text);
			if (!parsedHistoryArtifacts.ok) {
				throw new ArtifactParseError({
					kind: "artifact-parse-validation",
					code: parsedHistoryArtifacts.code,
					pass: "history",
					requestedModel: historyOutput.requestedModel,
					httpStatus: historyOutput.httpStatus,
				});
			}
			historyArtifacts = parsedHistoryArtifacts.artifacts;
			markContinuationArtifact(runtime, ownerEventId, "modeled", undefined);
		} catch (error) {
			if (ownerStillActive()) {
				recordContinuationSynthesisFailure(runtime, ownerEventId, normalizeSynthesisFailure(error));
				markContinuationArtifact(runtime, ownerEventId, "aborted", SYNTHESIS_ABORT_MESSAGE);
			}
			// Cancelling discards the compaction Pi already interrupted the turn for, so the
			// default is to let Pi save its own summary and fail only the owned handoff.
			if (config.synthesisFailureFallback === "cancel") return { cancel: true };
			if (ctx.hasUI) ctx.ui.notify(SYNTHESIS_NATIVE_FALLBACK, "warning");
			return undefined;
		}
		const continuationArtifactWriteId = config.continuationArtifactMode === "always" ? randomUUID() : undefined;
		if (continuationArtifactWriteId) {
			pendingOutputWrites.set(continuationArtifactWriteId, {
				path: resolvedProjectContext.continuationArtifactPath,
				content: historyArtifacts.briefMarkdown,
				label: "continuation artifact",
				target: "continuation-artifact",
				eventId: ownerEventId,
				projectRoot: resolvedProjectContext.projectRoot,
				confirmOverwrite: false,
				allowOutsideRoot: false,
				allowSymlinkedAncestor: config.allowSymlinkedOutputDirectory,
			});
		}
		const agentGuideWriteStatus = decideAgentGuideWriteStatus(config.agentGuideSyncMode, historyArtifacts.agentGuideMd);
		const agentGuideWriteId = agentGuideWriteStatus === "replacement-pending" ? randomUUID() : undefined;
		if (agentGuideWriteId && historyArtifacts.agentGuideMd) {
			pendingOutputWrites.set(agentGuideWriteId, {
				path: resolvedProjectContext.agentGuidePath,
				content: historyArtifacts.agentGuideMd,
				label: "agent guide",
				target: "agent-guide",
				eventId: ownerEventId,
				projectRoot: resolvedProjectContext.projectRoot,
				confirmOverwrite: config.agentGuideOverwritePolicy === "confirm",
				allowOutsideRoot: config.agentGuideAllowOutsideProject,
				allowSymlinkedAncestor: config.allowSymlinkedOutputDirectory,
			});
		}
		planContinuationOutputWrites(
			runtime,
			ownerEventId,
			{
				continuationArtifact: continuationArtifactWriteId ? "pending" : "off",
				agentGuide: agentGuideWriteStatus === "replacement-pending"
					? "pending"
					: agentGuideWriteStatus === "no-replacement"
						? "no-replacement"
						: "off",
			},
		);
		const details = buildContinuationDetails(
			preparation.fileOps,
			continuationArtifactWriteId,
			agentGuideWriteId,
			agentGuideWriteStatus,
			historyArtifacts.agentGuideChangeReason,
			synthesis,
			ownerEventId,
		);
		// Synthesis can take minutes, so the kept boundary is re-anchored against the entries Pi
		// holds now instead of the pre-synthesis snapshot.
		let firstKeptEntryId = preparation.firstKeptEntryId;
		try {
			firstKeptEntryId = resolveKeptEntryBoundary(firstKeptEntryId, event.branchEntries, ctx.sessionManager.getBranch());
		} catch {
			warnInputOnce(ctx, "kept-boundary", KEPT_BOUNDARY_FALLBACK);
		}
		return {
			compaction: {
				summary: composeCompactionSummary(historyArtifacts.briefMarkdown, details, {
					appendCompactionMetadata: config.appendCompactionMetadata,
					appendReadFileTags: config.appendReadFileTags,
					appendModifiedFileTags: config.appendModifiedFileTags,
					handoffId: randomUUID(),
				}),
				firstKeptEntryId,
				tokensBefore: preparation.tokensBefore,
				details,
			},
		};
	});

	pi.on("session_compact", async (event, ctx) => {
		const activeEventId = getActiveContinuationEventId(runtime);
		const activeCompactionProofVerified = activeEventId !== undefined
			&& runtime.latestEvent?.id === activeEventId
			&& runtime.latestEvent.compactionProof.status === "verified";
		if (activeEventId && !event.fromExtension) {
			if (!activeCompactionProofVerified) {
				failContinuationCompactionProof(ctx, runtime, activeEventId, NATIVE_COMPACTION_FALLBACK_FAILURE);
			}
			return;
		}
		if (!event.fromExtension) return;
		const details = parseContinuationDetails(event.compactionEntry.details);
		if (activeEventId && !details) {
			if (!activeCompactionProofVerified) {
				failContinuationCompactionProof(ctx, runtime, activeEventId, INVALID_COMPACTION_PROOF_FAILURE);
			}
			return;
		}
		if (!details) return;
		if (!details.continuationEventId) {
			if (activeEventId && !activeCompactionProofVerified) {
				failContinuationCompactionProof(ctx, runtime, activeEventId, INVALID_COMPACTION_PROOF_FAILURE);
			}
			return;
		}
		if (activeEventId && details.continuationEventId !== activeEventId) return;
		const acceptedActiveProof = activeEventId !== undefined && details.continuationEventId === activeEventId
			? verifyContinuationCompactionProof(ctx, runtime, activeEventId, event.compactionEntry.id)
			: false;
		const ledgerOwnerId = details.continuationEventId;
		const canUpdateLedger = isActiveRunningContinuationEvent(runtime, ledgerOwnerId);
		const ledger = canUpdateLedger
			? buildLedgerSnapshot(event.compactionEntry.summary, ledgerOwnerId, event.compactionEntry.id)
			: undefined;
		if (ledger) runtime.latestLedger = ledger;
		// Dispatch first: every step below is best-effort side work, and a failure there must
		// never leave the event running with no timer left to settle it.
		if (acceptedActiveProof && activeEventId) {
			dispatchVerifiedContinuationResume(ctx, runtime, activeEventId);
		}
		const claimedWrites: PendingOutputWrite[] = [];
		for (const writeId of [details.continuationArtifactWriteId, details.agentGuideWriteId]) {
			if (!writeId) continue;
			const pending = pendingOutputWrites.get(writeId);
			pendingOutputWrites.delete(writeId);
			if (!pending) continue;
			if (!isActiveRunningContinuationEvent(runtime, pending.eventId)) continue;
			claimedWrites.push(pending);
		}
		// Detached on purpose: the resume is already dispatched, and a deferred write that outlives
		// this context must not surface as an unhandled rejection.
		void runPendingOutputWrites(ctx, claimedWrites).catch(() => undefined);
		if (ctx.hasUI && details.agentGuideWriteStatus === "no-replacement" && details.agentGuideChangeReason) {
			ctx.ui.notify("Agent guide unchanged; no full replacement was produced.", "info");
		}
		if (!ledger) return;
		try {
			const projectContext = await resolveProjectContext(pi, ctx.cwd, ctx.sessionManager.getSessionId());
			const config = loadContinuationConfig(projectContext.projectRoot, isProjectScopeTrusted(ctx, projectContext.projectRoot));
			if (config.enabled && config.showAfterCompact) {
				ledgerOverlay.showSoon(ctx, ledger, (reason) => {
					if (ctx.hasUI) ctx.ui.notify(`Could not open Continuation Ledger: ${reason}`, "error");
				});
			}
		} catch {
			if (ctx.hasUI) ctx.ui.notify("Could not open Continuation Ledger: settings were unreadable.", "warning");
		}
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		shuttingDown = true;
		abandonActiveContinuationEvent(runtime, "Pi session shut down before continuation finished settling.");
		pendingOutputWrites.clear();
		releaseResumeSettlementWaiters(undefined);
		clearWorkingVisuals(ctx, runtime);
		ledgerOverlay.clear();
		runtime.compactionRunning = false;
		runtime.guardFailureKey = undefined;
		runtime.lastNoCompactableGuardKey = undefined;
		runtime.pendingCompactionRequest = undefined;
		resetContinuationChainBudget(runtime);
		clearResumeStartTimeout(runtime);
		clearPendingResumeDispatch(runtime);
		runtime.awaitingResumeEventId = undefined;
	});
}
