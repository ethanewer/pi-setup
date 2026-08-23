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

import { carryFileLists, type CompactionEntryLike } from "./carry-files.js";
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
import { createOnceNotifier, describe, retryCallbacks } from "./util.js";

export default function contextHandoffExtension(pi: ExtensionAPI) {
	const notifyOnce = createOnceNotifier();
	let config: ExtensionConfig | null = null;
	let configWarned = false;
	const resumeGuard = new ResumeGuard();
	// Set by session_before_compact, read by session_compact: only the former is handed the
	// branch entries needed to see how the last assistant message ended.
	let lastCompactionFollowedTruncation = false;
	// How the most recent low-level run ended, captured from agent_end because agent_settled
	// carries no payload.
	let lastRunStopReason: string | undefined;

	/**
	 * Single cache shared with the fold half: one config file, loaded once, warning once.
	 * Never throws — a broken config degrades to defaults, never to a disturbed request.
	 */
	const getConfig = (ctx: ExtensionContext): ExtensionConfig => {
		if (config) return config;
		const loaded = loadExtensionConfig();
		config = loaded.config;
		if (loaded.warnings.length > 0 && !configWarned) {
			configWarned = true;
			notifyOnce(ctx, loaded.warnings.join("\n"), "warning");
		}
		return config;
	};

	// The mid-run fold half. Registered first so its session_compact fold-invalidation runs
	// ahead of the resume logic below — mirroring the order the two standalone packages
	// subscribed in.
	registerFold(pi, getConfig);

	pi.on("session_before_compact", async (event, ctx) => {
		// Pi's SessionEntry union is wider than the structural shapes these two readers
		// declare; the fields they use are exactly the ones present at runtime.
		const branchEntries = event.branchEntries as unknown as EntryLike[];
		lastCompactionFollowedTruncation = lastAssistantWasTruncated(branchEntries);
		const config = getConfig(ctx).handoff;

		if (!config.enabled) return undefined;

		const model = ctx.model;
		if (!model) return undefined;

		try {
			const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
			// An unresolvable key would only surface as a provider error mid-compaction;
			// deferring to Pi is both quieter and more likely to work, since Pi resolves
			// auth for the same call through its own path.
			if (!auth.ok) return undefined;
			const focus = buildHandoffFocus({
				reason: event.reason,
				willRetry: event.willRetry,
				extra: config.focus,
				inherited: event.customInstructions,
			});

			const compaction = await compact(
				event.preparation,
				model,
				auth.apiKey,
				// Pi's own exported types disagree here (ProviderHeaders vs Record<string, string>);
				// the runtime value is one headers object passed through unchanged.
				auth.headers as Record<string, string> | undefined,
				focus,
				event.signal,
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
			// one, so fall through to Pi instead.
			if (!compaction || typeof compaction.summary !== "string" || compaction.summary.trim().length === 0) {
				notifyOnce(ctx, "pi-context-handoff: empty handoff brief; using Pi's own compaction.", "warning");
				return undefined;
			}

			// Pi refuses to read details from a hook-produced compaction, so it will never
			// carry this entry's file lists into the next one. Merge them here or the
			// accumulated read/modified lists restart empty at every boundary.
			return { compaction: carryFileLists(compaction, branchEntries as unknown as CompactionEntryLike[]) };
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

	// Cheapest resume point: session_compact is awaited before Pi's
	// `return this.agent.hasQueuedMessages()`, so a message queued here continues the same run.
	pi.on("session_compact", (event, ctx) => {
		const decision = resumeGuard.decide(lastCompactionFollowedTruncation, event.willRetry === true);
		lastCompactionFollowedTruncation = false;
		if (decision !== "ignore") sendResume(decision, ctx);
	});

	// Backstop. Several ways Pi ends a run never emit session_compact at all — a compaction
	// that threw, nothing to compact, an aborted compaction, or overflow recovery that has
	// already spent its single retry. agent_settled fires on all of them.
	pi.on("agent_end", (event) => {
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
		const decision = resumeGuard.decideOnSettled(lastRunStopReason, forced);
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
