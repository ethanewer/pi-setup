/**
 * pi-context-handoff
 *
 * Makes Pi's compaction summary a usable handoff brief for a long autonomous run, folds
 * context mid-run the way Codex does so a single run can never overshoot the window, and
 * resumes a run Pi abandoned at a compaction boundary. It must not be able to stop a run:
 * it never calls ctx.abort(), never returns { cancel: true }, and every failure path in
 * both halves degrades to stock Pi behavior.
 *
 * This package is one set of machinery under one config. Its concerns stay separate:
 *
 *   - Handoff (this file, session_before_compact): Pi only decides *when* to compact; this
 *     shapes *what the summary says*, calling Pi's own compact() with handoff-focus
 *     instructions and a retry policy, falling back to native compaction on any failure.
 *   - Fold (fold-hook.ts + fold.ts, the context hook): Pi's threshold check runs only
 *     between runs, so one long run could overshoot the window and die. The fold shapes the
 *     request mid-flight, Codex-style, without rewriting history. Every failure path sends
 *     the original messages — byte-for-byte the behaviour of not installing this package.
 *   - Resume (resume.ts, session_compact / agent_end / agent_settled): when Pi ends a run
 *     on a truncated reply or provider error — a case Pi's overflow test misses — this
 *     queues a resume message so agent.continue() keeps the run going. Never resumes
 *     stop/aborted; gives up after 3 consecutive unfinished resumes. It can never stop a
 *     run.
 *
 * The two compaction halves share one config file: handoff keys sit at the top level (as
 * before), and fold settings live under the optional "fold" object.
 */

import { compact, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

import { carryFileLists, type CompactionEntryLike, stripFileLists } from "./carry-files.js";
import { type ExtensionConfig, loadExtensionConfig } from "./config.js";
import { registerFold } from "./fold-hook.js";
import { buildHandoffFocus } from "./instructions.js";
import {
	type EntryLike,
	FORCE_RESUME_ENV,
	GAVE_UP_TEXT,
	isUnfinishedStop,
	lastAssistantWasTruncated,
	RESUME_MESSAGE_TYPE,
	RESUME_TEXT,
	ResumeGuard,
} from "./resume.js";
import { boundedSignal, createOnceNotifier, describe, judgeSummary, retryCallbacks, withAuthBaseUrl } from "./util.js";

export default function contextHandoffExtension(pi: ExtensionAPI) {
	const notifyOnce = createOnceNotifier();
	let config: ExtensionConfig | null = null;
	let configWarnings: string[] = [];
	const resumeGuard = new ResumeGuard();
	// Set by session_before_compact, read by session_compact: only the former is handed the
	// branch entries needed to see how the last assistant message ended.
	let lastCompactionFollowedTruncation = false;
	// How the most recent low-level run ended, captured from agent_end because agent_settled
	// carries no payload.
	let lastRunStopReason: string | undefined;
	// Whether that run's own signal was aborted, which is how a user cancel is distinguished
	// from a provider error that also settles as stopReason "error".
	let lastRunAborted = false;

	/**
	 * Single cache shared with the fold half: one config file, loaded once, warning once.
	 * Never throws — a broken config degrades to defaults, never to a disturbed request.
	 */
	const getConfig = (ctx: ExtensionContext): ExtensionConfig => {
		if (!config) {
			const loaded = loadExtensionConfig();
			config = loaded.config;
			configWarnings = loaded.warnings;
		}
		if (configWarnings.length > 0) {
			// `notifyOnce` dedupes and marks a message seen only once a UI can show it, so a
			// headless first read no longer consumes the warning for the whole session.
			notifyOnce(ctx, configWarnings.join("\n"), "warning");
		}
		return config;
	};

	// The mid-run fold half. Registered first so its session_compact fold-invalidation runs
	// ahead of the resume logic below — mirroring the order the two standalone packages
	// subscribed in.
	registerFold(pi, getConfig);

	// A fresh session gets a fresh config read: the file may have been edited between
	// sessions, and the once-per-session warnings should be allowed to fire again.
	pi.on("session_start", () => {
		config = null;
		configWarnings = [];
		notifyOnce.reset();
		resumeGuard.reset();
		lastCompactionFollowedTruncation = false;
		lastRunStopReason = undefined;
		lastRunAborted = false;
	});

	pi.on("session_before_compact", async (event, ctx) => {
		// Pi's SessionEntry union is wider than the structural shapes these two readers
		// declare; the fields they use are exactly the ones present at runtime.
		const branchEntries = event.branchEntries as unknown as EntryLike[];
		lastCompactionFollowedTruncation = lastAssistantWasTruncated(branchEntries);
		const config = getConfig(ctx).handoff;

		if (!config.enabled) return undefined;

		const model = ctx.model;
		if (!model) return undefined;

		// Bound the summarization. Pi's global undici idle timeout covers inactivity, not total
		// duration, so a slow-but-flowing stream or the retry schedule can outlast it; this caps
		// the whole call. Without it a stalled compaction has no exit but Esc.
		const bound = boundedSignal(event.signal, config.summarizeTimeoutMs);
		try {
			const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
			// An unresolvable key would only surface as a provider error mid-compaction;
			// deferring to Pi is both quieter and more likely to work, since Pi resolves
			// auth for the same call through its own path.
			if (!auth.ok) return undefined;
			// Pi's own summarization path applies the auth-resolved base URL
			// (`_getSummarizationRequestAuth`); without it a gateway/region/Azure endpoint
			// would be dropped and the request sent somewhere else.
			const requestModel = withAuthBaseUrl(model, auth.baseUrl);
			const focus = buildHandoffFocus({
				reason: event.reason,
				willRetry: event.willRetry,
				extra: config.focus,
				inherited: event.customInstructions,
			});

			const compaction = await compact(
				event.preparation,
				requestModel,
				auth.apiKey,
				// Pi's own exported types disagree here (ProviderHeaders vs Record<string, string>);
				// the runtime value is one headers object passed through unchanged.
				auth.headers as Record<string, string> | undefined,
				focus,
				bound.signal,
				ctx.thinkingLevel,
				undefined,
				// Provider-scoped environment: gateway ids, regions, endpoints, proxies.
				// Dropping it pointed the summarization request at a differently configured
				// provider than the one the session itself is using.
				auth.env,
				config.retry,
				// Pi drives its retry indicator through these. Without them a compaction that
				// was retrying looked identical to one that had hung.
				retryCallbacks(ctx, "context-handoff", "handoff brief"),
			);

			// A summary Pi cannot use is worse than none: returning a malformed
			// CompactionResult would replace a working native compaction with a broken
			// one, so fall through to Pi instead. The file lists `compact()` appends are
			// stripped first, or a summary with no brief at all would look non-empty.
			// The deadline is judged before the text: an aborted stream resolves with the
			// partial summary, so a fired bound makes whatever streamed untrustworthy. The
			// typeof guard keeps a malformed result on the empty-brief path instead of throwing
			// out of stripFileLists and reporting a confusing fallback.
			const summaryText =
				compaction && typeof compaction.summary === "string" ? stripFileLists(compaction.summary) : undefined;
			const verdict = judgeSummary({
				text: summaryText,
				timedOut: bound.timedOut(),
				userAborted: event.signal.aborted,
			});
			if (verdict.use) {
				if (compaction) {
					return { compaction: carryFileLists(compaction, branchEntries as unknown as CompactionEntryLike[]) };
				}
				return undefined;
			}

			// A user cancel is not a fault and needs no warning; Pi's own compaction takes over.
			if (verdict.reason !== "aborted" && config.notifyOnFallback) {
				notifyOnce(
					ctx,
					verdict.reason === "timed-out"
						? `pi-context-handoff: handoff brief timed out after ${Math.round(config.summarizeTimeoutMs / 1000)}s; using Pi's own compaction.`
						: "pi-context-handoff: empty handoff brief; using Pi's own compaction.",
					"warning",
				);
			}
			return undefined;
		} catch (error) {
			// Includes the abort case. Pi's own compaction path handles an aborted
			// signal, so handing back undefined stays correct there too.
			if (config.notifyOnFallback) {
				notifyOnce(
					ctx,
					`pi-context-handoff: falling back to Pi's compaction (${describe(error)}).`,
					"warning",
				);
			}
			return undefined;
		} finally {
			bound.dispose();
		}
	});

	const sendResume = (decision: "resume" | "give-up", ctx: ExtensionContext) => {
		try {
			pi.sendMessage(
				{
					customType: RESUME_MESSAGE_TYPE,
					content: decision === "resume" ? RESUME_TEXT : GAVE_UP_TEXT,
					display: true,
					details: { consecutiveResumes: resumeGuard.consecutiveResumes },
				},
				// Exactly the shape the monitor uses, which is the shape observed to resume a
				// run in production. "give-up" still sends: the run is ending either way, and
				// a visible reason beats silence.
				{ triggerTurn: decision === "resume", deliverAs: "steer" },
			);
		} catch (error) {
			// A refused injection must never turn a survivable stop into a crash.
			notifyOnce(ctx, `pi-context-handoff: could not resume the run (${describe(error)}).`, "warning");
		}
	};

	// Pi emits this when a compaction fails or is aborted. An aborted compaction is the user
	// pressing Esc; without recording it, the agent_settled backstop below would resume the run
	// from the stop reason that triggered the compaction and defeat the cancel.
	pi.on("session_compact_failed", (event) => {
		if (event.aborted) resumeGuard.noteCompactionAborted(event.reason);
	});

	// Cheapest resume point: session_compact is awaited before Pi's
	// `return this.agent.hasQueuedMessages()`, so a message queued here continues the same run.
	pi.on("session_compact", (event, ctx) => {
		// A deliberate /compact is not a rescue.
		if (event.reason === "manual") {
			lastCompactionFollowedTruncation = false;
			return;
		}
		const decision = resumeGuard.decide(
			lastCompactionFollowedTruncation,
			event.willRetry === true,
			event.reason,
			getConfig(ctx).resume.enabled,
		);
		lastCompactionFollowedTruncation = false;
		if (decision !== "ignore") sendResume(decision, ctx);
	});

	// Backstop. Several ways Pi ends a run never emit session_compact at all — a compaction
	// that threw, nothing to compact, an aborted compaction, or overflow recovery that has
	// already spent its single retry. agent_settled fires on all of them.
	pi.on("agent_end", (event, ctx) => {
		// A new agent loop is running (a queued-message continuation is another loop). Any cancel
		// from the previous loop is spent, so the backstop is armed again for this one.
		resumeGuard.noteAgentBoundary();
		// A user Esc aborts the run signal and leaves the agent with a provider error, so the
		// signal is the only reliable way to tell a cancel from a real fault. The three cases
		// seen in practice are stopReason "error" with "The operation was aborted", "aborted",
		// and a clean "length" from an earlier truncation. Only the last should resume.
		lastRunAborted = ctx.signal?.aborted === true;
		// Reset first: a run that dies before producing an assistant message must not be judged
		// by the previous run's stop reason.
		lastRunStopReason = undefined;
		const messages = (event as { messages?: Array<{ role?: string; stopReason?: string }> }).messages ?? [];
		for (let i = messages.length - 1; i >= 0; i--) {
			if (messages[i]?.role === "assistant") {
				lastRunStopReason = messages[i]?.stopReason;
				return;
			}
		}
	});

	pi.on("agent_settled", (_event, ctx) => {
		// The seam fires once: it is cleared here so a forced resume cannot loop.
		const forced = process.env[FORCE_RESUME_ENV] === "1";
		if (forced) delete process.env[FORCE_RESUME_ENV];
		const enabled = getConfig(ctx).resume.enabled;
		const decision =
			enabled || forced
				? resumeGuard.decideOnSettled(lastRunStopReason, forced, lastRunAborted)
				: "ignore";
		lastRunAborted = false;
		if (decision === "ignore") {
			// A run that ended cleanly clears the streak so an unrelated stop much later does
			// not inherit an old count.
			if (!isUnfinishedStop(lastRunStopReason)) resumeGuard.noteHealthyTurn();
			resumeGuard.endRun();
			lastRunStopReason = undefined;
			return;
		}
		sendResume(decision, ctx);
		resumeGuard.endRun();
		lastRunStopReason = undefined;
	});
}
