/**
 * pi-codex-compaction
 *
 * Compacts context the way Codex does: inside the run, before every LLM call, instead of
 * only between runs.
 *
 * The gap this closes
 * -------------------
 * Pi evaluates its compaction threshold in exactly two places, both outside an agent run:
 * `_handlePostAgentRun` after `agent.prompt()` returns, and before a new prompt. Everything
 * in between — every LLM call and tool result of one long autonomous run — accumulates
 * unchecked, which is how a run reaches 120% of its context window and dies on a truncated
 * reply. `ctx.compact()` cannot help, because it starts by disconnecting and aborting the
 * agent.
 *
 * Codex has no such gap: `turn.rs:493` checks the budget after every sampling request and
 * compacts right there, then `continue`s the loop. Compaction is a step in the loop rather
 * than a verdict on whether the loop survives.
 *
 * Pi's `context` hook is the same position in the loop — "fired before each LLM call, can
 * modify messages", and the array it returns is what the provider receives. So this
 * extension does what Codex does, at the point where Codex does it.
 *
 * What it is not
 * --------------
 * It does not rewrite session history. Codex calls `replace_compacted_history`; a `context`
 * handler only shapes one request. So the fold is recomputed and re-applied on every call,
 * the session file keeps everything, and every failure path returns the original messages —
 * which is byte-for-byte the behaviour of not installing this package. Codex, by contrast,
 * ends the turn when its compaction fails (turn.rs:504). Trading Codex's persistence for
 * that fallback is the central design decision here.
 *
 * It also does not replace Pi's own compaction or pi-context-handoff, and is not in tension
 * with them. Pi's between-runs compaction is the one that truly shrinks history and is
 * still wanted; this only keeps a *single* long run inside the window until that can happen.
 *
 * Reading order: fold.ts holds every decision and is pure; this file is the plumbing.
 */

import {
	calculateContextTokens,
	convertToLlm,
	estimateTokens,
	generateSummary,
	type ExtensionAPI,
	type ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import { type CodexCompactionConfig, loadCodexCompactionConfig } from "./config.js";
import {
	applyFold,
	type FoldState,
	fingerprint,
	isFoldValid,
	measure,
	type Metrics,
	type MessageLike,
	dropOldest,
	looksLikeSizeError,
	planFoldUnderPressure,
	plainSummaryMessage,
	shouldFold,
	syntheticCount,
	triggerTokens,
	trustUsageFrom,
} from "./fold.js";
import { buildFoldFocus } from "./instructions.js";

/**
 * Test seam. A 245,000-token conversation cannot be produced on demand, so this overrides
 * the trigger with an absolute token count and is the only way to exercise a real fold end
 * to end. Mirrors PI_STT_FAKE_* in the voice fork and PI_CONTEXT_HANDOFF_FORCE_RESUME.
 */
export const FORCE_TRIGGER_ENV = "PI_CODEX_COMPACTION_FORCE_TRIGGER_TOKENS";

/** Custom session entry recording each fold. Persisted, never shown to the model. */
export const FOLD_ENTRY_TYPE = "codex-compaction-fold";

/** Pi does not export its `Model` type from the package root; take it from the context. */
type PiModel = NonNullable<ExtensionContext["model"]>;

/** Pi's own token accounting, so a message is never costed differently here than there. */
const metrics: Metrics = {
	estimate: (message) => estimateTokens(message as never),
	usageTokens: (usage) => calculateContextTokens(usage as never),
};

function forcedTrigger(): number | null {
	const raw = process.env[FORCE_TRIGGER_ENV];
	if (!raw) return null;
	const parsed = Number.parseInt(raw, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

/** Emitted at most once per distinct message, so a repeating fault cannot spam a long run. */
function createOnceNotifier() {
	const seen = new Set<string>();
	return (ctx: ExtensionContext, message: string, variant: "warning" | "info") => {
		if (seen.has(message)) return;
		seen.add(message);
		if (!ctx.hasUI) return;
		try {
			ctx.ui.notify(message, variant);
		} catch {
			// A UI that refuses a notification must not affect the request.
		}
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

/**
 * Confirm Pi still renders a `compactionSummary` message into the request.
 *
 * `createCompactionSummaryMessage` is not exported from the package root, so the message is
 * built by hand in fold.ts. That is the one internal shape this extension depends on, and an
 * unrendered summary would be the worst possible failure — history folded away and nothing
 * put in its place. Checking it once per session against Pi's own `convertToLlm` turns that
 * into a fallback instead of a silent hole.
 */
function summaryMessageSurvivesConversion(fold: FoldState): boolean {
	try {
		const converted = convertToLlm([applyFold([{ role: "user", content: "probe" }], fold)[0]] as never);
		if (!Array.isArray(converted) || converted.length === 0) return false;
		const text = JSON.stringify(converted);
		return text.includes(fold.summary.slice(0, 24));
	} catch {
		return false;
	}
}

export default function codexCompactionExtension(pi: ExtensionAPI) {
	const notifyOnce = createOnceNotifier();
	let config: CodexCompactionConfig | null = null;
	let fold: FoldState | null = null;
	let summarizing = false;
	let consecutiveFailures = 0;
	let abandoned = false;
	let folds = 0;
	let summaryShapeChecked = false;
	let usePlainSummary = false;
	let lastTokens: number | null = null;
	/** Folds since the request was last measured under the trigger. See the guard below. */
	let foldsSinceUnderTrigger = 0;
	let lastRung: number | "latest" | null = null;
	/**
	 * The model in use before the most recent switch, for the downshift case below. Held whole
	 * rather than as a stripped copy: both `getApiKeyAndHeaders` and `generateSummary` need the
	 * provider, base URL and token limits, not just the id and window.
	 */
	let previousModel: PiModel | undefined;

	const settings = (ctx: ExtensionContext): CodexCompactionConfig => {
		if (config) return config;
		const loaded = loadCodexCompactionConfig();
		config = loaded.config;
		if (loaded.warning) notifyOnce(ctx, loaded.warning, "warning");
		return config;
	};

	const status = (ctx: ExtensionContext, message: string | undefined) => {
		if (!ctx.hasUI) return;
		try {
			ctx.ui.setStatus("codex-compaction", message);
		} catch {
			// Status is decoration; never let it affect the request.
		}
	};

	/**
	 * Summarize a stretch of history, shrinking the request when the summarization call is
	 * itself too big. That retry is Codex's (compact.rs:215-225, `remove_first_item()` in a
	 * loop) and is the case Pi has no answer for: its compaction either fits or fails.
	 */
	const summarize = async (
		ctx: ExtensionContext,
		cfg: CodexCompactionConfig,
		prefix: MessageLike[],
		previousSummary: string | undefined,
		pinned: boolean,
	): Promise<string | null> => {
		const active = ctx.model;
		if (!active) return null;

		// Codex compacts with the *previous* model when the session has just moved to one with a
		// smaller window (maybe_run_previous_model_inline_compact, turn.rs:749). The reason is
		// exact: the history was accumulated under the old window, so the new model may be
		// unable to read it at all, and the summarization would fail for a reason no amount of
		// retrying fixes. Same gate as Codex's — different model, and the old window was larger.
		let model = active;
		if (
			previousModel &&
			previousModel.id !== active.id &&
			typeof previousModel.contextWindow === "number" &&
			previousModel.contextWindow > active.contextWindow
		) {
			const downshiftAuth = await ctx.modelRegistry.getApiKeyAndHeaders(previousModel);
			if (downshiftAuth.ok) {
				model = previousModel;
				notifyOnce(
					ctx,
					`pi-codex-compaction: folding with ${previousModel.id}, the wider window this history was written under.`,
					"info",
				);
			}
			// If its credential is gone, fall through to the active model: the trim ladder below
			// is then the only defence, which is still better than not folding.
		}

		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
		if (!auth.ok) {
			notifyOnce(ctx, "pi-codex-compaction: no usable credential; leaving the request unfolded.", "warning");
			return null;
		}
		const focus = buildFoldFocus({ pinned, extra: cfg.focus });
		let current = prefix;
		for (let attempt = 0; attempt <= cfg.maxTrimAttempts; attempt++) {
			try {
				status(ctx, attempt === 0 ? "folding context" : `folding context (trimmed ${attempt})`);
				const summary = await generateSummary(
					current as never,
					model,
					cfg.summaryReserveTokens,
					auth.apiKey,
					auth.headers,
					ctx.signal,
					focus,
					previousSummary,
					ctx.thinkingLevel,
					undefined,
					// Provider-scoped environment: gateway ids, regions, endpoints, proxies.
					// Dropping it would point this call at a differently configured provider
					// than the session's own.
					auth.env,
					cfg.retry,
					{
						onRetryScheduled: (a: number, max: number, delayMs: number) =>
							status(ctx, `folding context: retry ${a}/${max} in ${Math.round(delayMs / 1000)}s`),
						onRetryAttemptStart: () => status(ctx, "folding context: retrying"),
						onRetryFinished: () => status(ctx, "folding context"),
					},
				);
				if (typeof summary === "string" && summary.trim().length > 0) return summary;
				return null;
			} catch (error) {
				// An abort is the user stopping the run, not a fault: leave the counters alone
				// and let the request go out unfolded. Codex propagates Interrupted the same way.
				if (ctx.signal?.aborted) return null;
				// Trim only for the error trimming can fix. Codex branches on a typed
				// ContextWindowExceeded here; anything else has already exhausted the retry
				// policy passed to generateSummary, so shrinking the prefix would just spend the
				// remaining budget on a fault that is not about size.
				if (!looksLikeSizeError(error)) {
					notifyOnce(ctx, `pi-codex-compaction: could not fold (${describe(error)}).`, "warning");
					return null;
				}
				if (attempt >= cfg.maxTrimAttempts || current.length <= 1) {
					notifyOnce(
						ctx,
						`pi-codex-compaction: prefix still too large after ${attempt} trim(s) (${describe(error)}).`,
						"warning",
					);
					return null;
				}
				current = dropOldest(current, 0.25, metrics);
			}
		}
		return null;
	};

	pi.on("context", async (event, ctx) => {
		if (abandoned) return undefined;
		const cfg = settings(ctx);
		if (!cfg.enabled) return undefined;

		const model = ctx.model;
		const contextWindow = model?.contextWindow;
		if (!model || typeof contextWindow !== "number" || contextWindow <= 0) return undefined;

		const original = event.messages as unknown as MessageLike[];
		if (fold && !isFoldValid(original, fold)) {
			// Almost always Pi's own between-runs compaction rewriting history, which is a
			// better outcome than this fold and supersedes it.
			fold = null;
		}
		const applied = fold ? applyFold(original, fold) : original;

		// Overhead is the system prompt plus tool schemas: both are in every provider usage
		// number and in none of these messages, so the estimate path has to add them back or
		// the two ways of measuring would answer to different thresholds.
		let overhead = cfg.toolOverheadTokens;
		try {
			overhead += Math.ceil(ctx.getSystemPrompt().length / 4);
		} catch {
			// getSystemPrompt is only unavailable in odd modes; the tool allowance still applies.
		}
		const measurement = measure(applied, metrics, { trustUsageFrom: trustUsageFrom(fold), overhead });
		lastTokens = measurement.tokens;

		const forced = forcedTrigger();
		const over =
			forced !== null
				? measurement.tokens >= forced
				: shouldFold(measurement.tokens, contextWindow, cfg.triggerPercent);
		// A fold already in force must be re-applied on every call; forgetting to would send
		// the full history again and undo the whole mechanism.
		if (!over) {
			foldsSinceUnderTrigger = 0;
			return fold ? { messages: applied as never } : undefined;
		}

		// The agent loop is serial, so this should be unreachable; if some other path ever
		// re-enters, the existing fold is still the right answer and a second concurrent
		// summarization is not.
		if (summarizing) return fold ? { messages: applied as never } : undefined;

		// Folding is meant to get the request under the trigger. If it has not managed that after
		// a couple of attempts, more folding is not the answer and continuing would keep eating
		// context for nothing — the failure mode observed in verification, where a run folded on
		// every call and lost the thread. Codex needs no such guard: its compaction reduces to
		// roughly 20k, so far below any trigger that its own comment says an infinite loop is not
		// a concern. Keeping a recent tail is what makes this reachable here, so this guard is
		// part of the price of that divergence.
		if (foldsSinceUnderTrigger >= cfg.maxFoldsWithoutProgress) {
			notifyOnce(
				ctx,
				`pi-codex-compaction: ${foldsSinceUnderTrigger} folds did not get under the trigger; standing down and leaving it to Pi.`,
				"warning",
			);
			return fold ? { messages: applied as never } : undefined;
		}

		const plan = planFoldUnderPressure(
			original,
			fold,
			measurement.tokens,
			cfg,
			metrics,
			forced ?? triggerTokens(contextWindow, cfg.triggerPercent),
		);
		if (!plan) {
			// Over the trigger and not even the last rung — no recent tail at all — found
			// anything to fold. Pi's own overflow recovery is the next line of defence, so say so
			// rather than pretend.
			notifyOnce(
				ctx,
				`pi-codex-compaction: over ${forced ?? triggerTokens(contextWindow, cfg.triggerPercent)} tokens but nothing further can be folded; leaving it to Pi.`,
				"warning",
			);
			return fold ? { messages: applied as never } : undefined;
		}
		if (plan.rung !== 1) {
			// Worth saying out loud: the recent tail is the in-flight working state, and giving it
			// up is a real loss even though it beats an oversized request.
			notifyOnce(
				ctx,
				`pi-codex-compaction: recent context did not fit on its own; folded with a reduced tail (${plan.rung}).`,
				"warning",
			);
		}

		summarizing = true;
		let summary: string | null;
		try {
			summary = await summarize(ctx, cfg, plan.prefix, fold?.summary, plan.pinned.length > 0);
		} finally {
			summarizing = false;
			status(ctx, undefined);
		}

		if (summary === null) {
			if (!ctx.signal?.aborted) {
				consecutiveFailures++;
				if (consecutiveFailures >= cfg.maxFailures) {
					abandoned = true;
					notifyOnce(
						ctx,
						`pi-codex-compaction: ${consecutiveFailures} folds failed in a row; disabled for this session.`,
						"warning",
					);
				}
			}
			return fold ? { messages: applied as never } : undefined;
		}
		consecutiveFailures = 0;

		const next: FoldState = {
			cutIndex: plan.cutIndex,
			summary,
			pinned: plan.pinned,
			tokensBefore: plan.tokensBefore,
			// Frozen once: the synthetic messages must be byte-identical on every later call or
			// provider prefix caching is lost on all of them.
			timestamp: Date.now(),
			originalLength: original.length,
			headFingerprint: fingerprint(original[0]),
			boundaryFingerprint: fingerprint(original[plan.cutIndex - 1]),
		};

		if (!summaryShapeChecked) {
			summaryShapeChecked = true;
			usePlainSummary = !summaryMessageSurvivesConversion(next);
			if (usePlainSummary) {
				notifyOnce(
					ctx,
					"pi-codex-compaction: Pi no longer renders compactionSummary messages; using a plain user message instead.",
					"warning",
				);
			}
		}

		fold = next;
		folds++;
		foldsSinceUnderTrigger++;
		lastRung = plan.rung;
		let messages = applyFold(original, fold);
		if (usePlainSummary) messages = [plainSummaryMessage(fold), ...messages.slice(1)];
		// Forced onto the estimate path. Nothing in a just-folded array can carry usage from a
		// folded request — the newest assistant message is the one whose oversized reply caused
		// this fold — so trusting usage here reported the pre-fold size and made every fold look
		// like it had saved nothing. Observed in verification before it was fixed.
		const after = measure(messages, metrics, { trustUsageFrom: messages.length, overhead });

		// Record the fold in the session. Because the fold shapes the request and never the
		// history, a session file would otherwise contain no evidence that any of this
		// happened — and a mid-run behaviour change that leaves no trace is the exact failure
		// this repository keeps having to diagnose after the fact. A custom entry is the right
		// carrier: Pi persists it and does not put it in LLM context.
		try {
			pi.appendEntry(FOLD_ENTRY_TYPE, {
				at: new Date(next.timestamp).toISOString(),
				fold: folds,
				cutIndex: next.cutIndex,
				messagesFolded: plan.cutIndex,
				pinnedInstructions: next.pinned.length,
				/** Anything but 1 means the recent tail had to be reduced to make it fit. */
				pressureRung: plan.rung,
				tokensBefore: measurement.tokens,
				/** Estimated, not measured: no usage record for the folded request exists yet. */
				tokensAfterEstimated: after.tokens,
				measuredFromUsage: measurement.fromUsage,
				trigger: forced ?? triggerTokens(contextWindow, cfg.triggerPercent),
				contextWindow,
				summaryChars: summary.length,
			});
		} catch {
			// An audit trail must never be the reason a request fails.
		}
		if (cfg.notify) {
			// Not once-only: every fold is worth seeing, and there is one per ~200k tokens.
			if (ctx.hasUI) {
				try {
					ctx.ui.notify(
						`codex-compaction: folded ${plan.cutIndex} messages mid-run, ~${Math.round(measurement.tokens / 1000)}k tokens → ~${Math.round(after.tokens / 1000)}k estimated${plan.pinned.length > 0 ? `, ${plan.pinned.length} instruction(s) kept verbatim` : ""}.`,
						"info",
					);
				} catch {
					// Never let a notification affect the request.
				}
			}
		}
		if (folds > 1) {
			// Codex says this on every compaction (compact.rs:289). Once per session here: with a
			// fold roughly every 200k tokens, repeating it would be noise, and the advice does not
			// change on the third telling.
			notifyOnce(
				ctx,
				"pi-codex-compaction: long threads and repeated compaction make the model less accurate. Start a new session when the current task allows it.",
				"warning",
			);
		}
		return { messages: messages as never };
	});

	// A fold describes one linear history. Pi's own compaction, a fork, or tree navigation all
	// replace that history; the fingerprints in isFoldValid would catch it on the next call
	// anyway, but dropping it here means the next request is measured honestly rather than
	// against a fold that is about to be discarded.
	pi.on("session_compact", () => {
		fold = null;
	});
	pi.on("session_tree", () => {
		fold = null;
	});
	// Belt and braces. isFoldValid's fingerprints already reject a fold computed against another
	// session's history, but if a runtime is ever reused across a session replacement the next
	// request is measured honestly rather than against a fold about to be discarded.
	pi.on("session_start", () => {
		fold = null;
		previousModel = undefined;
	});

	pi.on("model_select", (event) => {
		previousModel = event.previousModel;
	});

	pi.registerCommand("codex-compaction", {
		description: "Show mid-run context folding state (Codex-style compaction)",
		handler: async (_args, ctx) => {
			const cfg = settings(ctx);
			const window = ctx.model?.contextWindow ?? 0;
			const trigger = forcedTrigger() ?? triggerTokens(window, cfg.triggerPercent);
			const stoodDown = foldsSinceUnderTrigger >= cfg.maxFoldsWithoutProgress;
			const lines = [
				`enabled: ${cfg.enabled && !abandoned}${abandoned ? " (stood down after repeated failures)" : ""}`,
				`trigger: ${trigger} tokens of ${window}${forcedTrigger() !== null ? " (forced via env)" : ` (${Math.round(cfg.triggerPercent * 100)}%)`}`,
				`last measured: ${lastTokens ?? "unknown"} tokens`,
				`folds this session: ${folds}${lastRung !== null && lastRung !== 1 ? ` (last one gave up part of the recent tail: ${lastRung})` : ""}`,
				fold
					? `active fold: ${fold.cutIndex} messages folded, ${fold.pinned.length} instruction(s) pinned, ${syntheticCount(fold)} synthetic message(s)`
					: "active fold: none",
			];
			// Only worth showing when it is not the boring answer, but worth showing loudly then:
			// a stood-down fold is otherwise indistinguishable from one that never needed to run.
			if (foldsSinceUnderTrigger > 0) {
				lines.push(
					`folds since under the trigger: ${foldsSinceUnderTrigger} of ${cfg.maxFoldsWithoutProgress}${stoodDown ? " - stood down, leaving it to Pi" : ""}`,
				);
			}
			if (ctx.hasUI) {
				try {
					ctx.ui.notify(lines.join("\n"), "info");
					return;
				} catch {
					// Fall through to stdout below.
				}
			}
			console.log(lines.join("\n"));
		},
	});
}
