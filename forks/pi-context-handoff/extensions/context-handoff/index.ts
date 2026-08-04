/**
 * pi-context-handoff
 *
 * Makes Pi's compaction summary a usable handoff brief for a long autonomous run,
 * and does nothing else.
 *
 * Design constraint, which is the whole reason this package exists: it must not be
 * able to stop a run. Pi compacts between agent runs and continues (agent-session's
 * _checkCompaction returns true and the loop in _runAgentPrompt carries on), and its
 * native summarization is retried. So this hooks session_before_compact, calls Pi's own
 * compact() with focus instructions plus a retry policy, and returns the result.
 *
 * An earlier version of this comment said Pi "compacts mid-turn". It does not, and the
 * distinction matters: _checkCompaction is only reached from _handlePostAgentRun, after
 * `await this.agent.prompt(...)` has returned (agent-session.js:744-750). Everything
 * inside one agentic run — every LLM call and tool result in it — accumulates with no
 * threshold check, so context can pass the model's window mid-run and stay there until
 * the run ends. Nothing here can change that, and nothing here should try: the only
 * extension-facing trigger, ctx.compact(), begins with _disconnectFromAgent() and
 * abort(), so calling it from a turn_end hook would kill the run it was meant to protect.
 * See docs/LONG_RUNS.md.
 *
 * It never calls ctx.abort() and never returns { cancel: true }. Every failure path
 * returns undefined, which means "Pi, do your own compaction" — the exact behaviour of
 * not having this package installed.
 *
 * The one thing it does send is a resume nudge, and only in a situation where the run is
 * otherwise already over. See resume.ts.
 */

import { compact, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

import { carryFileLists } from "./carry-files.js";
import {
	FORCE_RESUME_ENV,
	GAVE_UP_TEXT,
	isUnfinishedStop,
	lastAssistantWasTruncated,
	RESUME_MESSAGE_TYPE,
	RESUME_TEXT,
	ResumeGuard,
} from "./resume.js";
import { type HandoffConfig, loadHandoffConfig } from "./config.js";
import { buildHandoffFocus } from "./instructions.js";

/** Emitted at most once per session per distinct message, so a repeating fault cannot spam. */
function createOnceNotifier() {
	const seen = new Set<string>();
	return (ctx: ExtensionContext, message: string, variant: "warning" | "info") => {
		if (seen.has(message)) return;
		seen.add(message);
		if (!ctx.hasUI) return;
		try {
			ctx.ui.notify(message, variant);
		} catch {
			// A UI that refuses a notification must not affect compaction.
		}
	};
}

/**
 * Pi passes its own callbacks to compact() so the TUI can show a retry indicator. Calling
 * compact() ourselves means supplying them, or a compaction that is quietly retrying a
 * failed provider call is indistinguishable from one that has hung.
 */
function retryCallbacks(ctx: ExtensionContext) {
	const say = (message: string | undefined) => {
		if (!ctx.hasUI) return;
		try {
			ctx.ui.setStatus("context-handoff", message);
		} catch {
			// Status is decoration; never let it affect the compaction.
		}
	};
	return {
		onRetryScheduled: (attempt: number, maxAttempts: number, delayMs: number) =>
			say(`handoff brief: retry ${attempt}/${maxAttempts} in ${Math.round(delayMs / 1000)}s`),
		onRetryAttemptStart: () => say("handoff brief: retrying"),
		onRetryFinished: () => say(undefined),
	};
}

function describe(error: unknown): string {
	if (error instanceof Error && typeof error.message === "string") return error.message;
	try {
		return String(error);
	} catch {
		return "unknown error";
	}
}

export default function contextHandoffExtension(pi: ExtensionAPI) {
	const notifyOnce = createOnceNotifier();
	let configWarned = false;
	const resumeGuard = new ResumeGuard();
	// Set by session_before_compact, read by session_compact: only the former is handed the
	// branch entries needed to see how the last assistant message ended.
	let lastCompactionFollowedTruncation = false;
	// How the most recent low-level run ended, captured from agent_end because agent_settled
	// carries no payload.
	let lastRunStopReason: string | undefined;

	pi.on("session_before_compact", async (event, ctx) => {
		lastCompactionFollowedTruncation = lastAssistantWasTruncated(event.branchEntries);
		let config: HandoffConfig;
		try {
			const loaded = loadHandoffConfig();
			config = loaded.config;
			if (loaded.warning && !configWarned) {
				configWarned = true;
				notifyOnce(ctx, loaded.warning, "warning");
			}
		} catch {
			// loadHandoffConfig is written not to throw; if it somehow does, defer to Pi.
			return undefined;
		}

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
				auth.headers,
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
				retryCallbacks(ctx),
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
			return { compaction: carryFileLists(compaction, event.branchEntries) };
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
