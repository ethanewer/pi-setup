/**
 * pi-context-handoff
 *
 * Makes Pi's compaction summary a usable handoff brief for a long autonomous run,
 * and does nothing else.
 *
 * Design constraint, which is the whole reason this package exists: it must not be
 * able to stop a run. Pi already compacts mid-turn and continues (agent-session's
 * _checkCompaction returns true and the agent loop carries on), and its native
 * summarization is retried. So this hooks session_before_compact, calls Pi's own
 * compact() with focus instructions plus a retry policy, and returns the result.
 *
 * It never calls ctx.abort(), never sends a message, and never returns
 * { cancel: true }. Every failure path returns undefined, which means "Pi, do your
 * own compaction" — the exact behaviour of not having this package installed.
 */

import { compact, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

import { carryFileLists } from "./carry-files.js";
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

	pi.on("session_before_compact", async (event, ctx) => {
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
}
