import { describe, expect, test } from "bun:test";

import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** Run `fn` with PI_CODING_AGENT_DIR pointed at a temp dir seeded with the given config files. */
function withAgentDir(files: Record<string, unknown>, fn: () => void): void {
	const dir = mkdtempSync(join(tmpdir(), "fold-config-test-"));
	const previous = process.env.PI_CODING_AGENT_DIR;
	mkdirSync(join(dir, "extensions"), { recursive: true });
	for (const [name, value] of Object.entries(files)) {
		writeFileSync(join(dir, "extensions", name), JSON.stringify(value));
	}
	process.env.PI_CODING_AGENT_DIR = dir;
	try {
		fn();
	} finally {
		if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = previous;
		rmSync(dir, { recursive: true, force: true });
	}
}

import {
	applyFold,
	collectPinned,
	DEFAULT_FOLD_SETTINGS,
	dropOldest,
	findFoldCut,
	findLatestCut,
	fingerprint,
	type FoldState,
	isCutPoint,
	isFoldValid,
	looksLikeSizeError,
	measure,
	mergePinned,
	messageText,
	type MessageLike,
	type Metrics,
	PINNED_PREFIX,
	pinnedInstructionsText,
	planFold,
	planFoldUnderPressure,
	shouldFold,
	syntheticCount,
	triggerTokens,
	trustUsageFrom,
} from "../forks/pi-context-handoff/extensions/context-handoff/fold";
import {
	DEFAULT_FOLD_CONFIG,
	loadExtensionConfig,
} from "../forks/pi-context-handoff/extensions/context-handoff/config";
import { buildFoldFocus } from "../forks/pi-context-handoff/extensions/context-handoff/instructions";

/**
 * Same shape as Pi's own estimateTokens (chars/4), which is what index.ts injects. Written
 * out here so the tests state token sizes in characters and stay readable.
 */
const metrics: Metrics = {
	estimate: (message) => Math.ceil(messageText(message).length / 4),
	usageTokens: (usage) => {
		const u = usage as Record<string, number>;
		return u.totalTokens || u.input + u.output + u.cacheRead + u.cacheWrite;
	},
};

const user = (text: string, timestamp = 1): MessageLike => ({
	role: "user",
	content: [{ type: "text", text }],
	timestamp,
});
const assistant = (text: string, usage?: Record<string, number>): MessageLike => ({
	role: "assistant",
	content: [{ type: "text", text }],
	usage,
	timestamp: 2,
});
const toolResult = (text: string): MessageLike => ({
	role: "toolResult",
	content: [{ type: "text", text }],
	timestamp: 3,
});
/** 4 chars per token, so `filler(n)` is n tokens. */
const filler = (tokens: number) => "x".repeat(tokens * 4);

const settings = { ...DEFAULT_FOLD_SETTINGS, keepRecentTokens: 100, minSavingTokens: 10, pinUserTokens: 50 };

describe("isCutPoint", () => {
	test("a tail may not begin with a tool result", () => {
		// Pi's linearization puts tool results immediately after the assistant message that
		// made the calls, so refusing this one role is what keeps a call and its results together.
		expect(isCutPoint(toolResult("out"))).toBe(false);
		expect(isCutPoint(user("hi"))).toBe(true);
		expect(isCutPoint(assistant("hi"))).toBe(true);
		expect(isCutPoint({ role: "compactionSummary", summary: "s" })).toBe(true);
	});

	test("an unrecognised role is not assumed safe", () => {
		// A role added by a future Pi version must not silently become a cut point.
		expect(isCutPoint({ role: "somethingNew" })).toBe(false);
		expect(isCutPoint(undefined)).toBe(false);
	});
});

describe("findFoldCut", () => {
	test("keeps roughly the recent budget and cuts at a valid boundary", () => {
		const messages = [user(filler(60)), assistant(filler(60)), user(filler(60)), assistant(filler(60))];
		// Walking back from the end, the budget of 100 is passed inside message 2, so the cut
		// lands on the first cut point at or after it.
		expect(findFoldCut(messages, 100, metrics)).toBe(2);
	});

	test("folds nothing when the whole conversation fits the recent budget", () => {
		const messages = [user(filler(5)), assistant(filler(5))];
		expect(findFoldCut(messages, 100, metrics)).toBe(0);
	});

	test("skips past tool results to the next real boundary", () => {
		const messages = [
			user(filler(60)),
			assistant(filler(60)),
			toolResult(filler(60)),
			toolResult(filler(60)),
			assistant(filler(10)),
		];
		const cut = findFoldCut(messages, 100, metrics);
		expect(isCutPoint(messages[cut])).toBe(true);
		expect(messages[cut].role).not.toBe("toolResult");
	});

	test("never cuts below minIndex, so a synthetic head cannot be folded away", () => {
		const messages = [
			{ role: "compactionSummary", summary: filler(50) },
			user(filler(60)),
			assistant(filler(60)),
			user(filler(60)),
		];
		expect(findFoldCut(messages, 100, metrics, 1)).toBeGreaterThanOrEqual(1);
	});
});

describe("measure", () => {
	test("prefers a real usage record over an estimate", () => {
		const messages = [user(filler(10)), assistant("done", { totalTokens: 5000 }), user(filler(10))];
		const result = measure(messages, metrics);
		expect(result.fromUsage).toBe(true);
		expect(result.tokens).toBe(5010);
	});

	test("falls back to estimation plus overhead when no usage exists", () => {
		const messages = [user(filler(10)), user(filler(10))];
		const result = measure(messages, metrics, { overhead: 100 });
		expect(result.fromUsage).toBe(false);
		// Overhead stands in for the system prompt and tool schemas, which a usage record
		// already includes; without it the two paths would answer to different thresholds.
		expect(result.tokens).toBe(120);
	});

	test("ignores usage recorded before the fold took effect", () => {
		// This is the bug the trustUsageFrom argument exists for. The assistant message that
		// triggered the fold carries the usage of the huge pre-fold request. Trusting it would
		// make the next call believe the folded request was still oversized and fold again,
		// discarding most of the conversation for nothing.
		const applied = [
			{ role: "compactionSummary", summary: filler(20) },
			assistant("the reply that overflowed", { totalTokens: 250_000 }),
			user(filler(10)),
		];
		const stale = measure(applied, metrics);
		expect(stale.tokens).toBeGreaterThan(200_000);
		const honest = measure(applied, metrics, { trustUsageFrom: 3 });
		expect(honest.fromUsage).toBe(false);
		expect(honest.tokens).toBeLessThan(100);
	});

	test("trustUsageFrom points past everything that existed when the fold was made", () => {
		const fold: FoldState = {
			cutIndex: 10,
			summary: "s",
			pinned: ["keep me"],
			tokensBefore: 1,
			timestamp: 0,
			originalLength: 14,
			headFingerprint: "",
			boundaryFingerprint: "",
		};
		// 2 synthetic messages + the 4 original messages that survived the cut.
		expect(syntheticCount(fold)).toBe(2);
		expect(trustUsageFrom(fold)).toBe(6);
		expect(trustUsageFrom(null)).toBe(0);
	});
});

describe("shouldFold", () => {
	test("matches Codex's 90% derivation and its >= comparison", () => {
		// Codex: (context_window * 9) / 10, compared with >=.
		expect(triggerTokens(272_000, 0.9)).toBe(244_800);
		expect(shouldFold(244_800, 272_000, 0.9)).toBe(true);
		expect(shouldFold(244_799, 272_000, 0.9)).toBe(false);
	});

	test("an unknown context window never triggers a fold", () => {
		expect(shouldFold(999_999, 0, 0.9)).toBe(false);
		expect(shouldFold(999_999, Number.NaN, 0.9)).toBe(false);
	});
});

describe("collectPinned", () => {
	test("keeps real user instructions verbatim, newest first, in chronological order", () => {
		const messages = [user("first thing"), assistant("ok"), user("second thing")];
		expect(collectPinned(messages, 50, metrics)).toEqual(["first thing", "second thing"]);
	});

	test("machine-generated user-rendered messages are not instructions", () => {
		// custom messages are how the monitor's events and the resume nudge reach the model;
		// pinning them would spend the budget meant for what the operator actually asked.
		const messages = [
			{ role: "custom", customType: "monitor", content: [{ type: "text", text: "watcher fired" }] },
			{ role: "bashExecution", command: "ls", output: "a" },
			user("the real instruction"),
		];
		expect(collectPinned(messages, 50, metrics)).toEqual(["the real instruction"]);
	});

	test("spends the budget newest-first, truncating the one that no longer fits", () => {
		// Codex's build_compacted_history_with_limit does exactly this: walk newest-first, and
		// when a message exceeds what is left, truncate it and stop rather than drop it.
		const messages = [user(filler(40)), user(filler(40))];
		const pinned = collectPinned(messages, 50, metrics);
		expect(pinned).toHaveLength(2);
		// Chronological order out, so the newest — kept whole — is last.
		expect(pinned[1]).toBe(filler(40));
		expect(pinned[0]).toContain("[instruction truncated]");
		expect(pinned[0].length).toBeLessThan(filler(40).length);
	});

	test("truncates one oversized instruction rather than losing it entirely", () => {
		const pinned = collectPinned([user(filler(200))], 10, metrics);
		expect(pinned).toHaveLength(1);
		expect(pinned[0]).toContain("[instruction truncated]");
		expect(pinned[0].length).toBeLessThan(filler(200).length);
	});

	test("a zero budget disables pinning", () => {
		expect(collectPinned([user("x")], 0, metrics)).toEqual([]);
	});
});

describe("mergePinned", () => {
	test("newer pins survive when the budget forces a choice", () => {
		const merged = mergePinned([filler(40)], [filler(40)], 50, metrics);
		expect(merged).toEqual([filler(40)]);
	});

	test("accumulates across folds while there is room", () => {
		expect(mergePinned(["a"], ["b"], 50, metrics)).toEqual(["a", "b"]);
	});
});

describe("applyFold", () => {
	const fold: FoldState = {
		cutIndex: 2,
		summary: "what happened so far",
		pinned: ["do the thing"],
		tokensBefore: 250_000,
		timestamp: 1234,
		originalLength: 4,
		headFingerprint: "",
		boundaryFingerprint: "",
	};

	test("summary first, then verbatim instructions, then the untouched tail", () => {
		const original = [user("old"), assistant("older"), user("recent"), assistant("newest")];
		const applied = applyFold(original, fold);
		expect(applied).toHaveLength(4);
		expect(applied[0].role).toBe("compactionSummary");
		expect(applied[0].summary).toBe("what happened so far");
		expect(applied[1].role).toBe("user");
		expect(messageText(applied[1])).toContain("do the thing");
		// The tail is passed through by reference: nothing in a live turn is rewritten.
		expect(applied[2]).toBe(original[2]);
		expect(applied[3]).toBe(original[3]);
	});

	test("is byte-identical across calls, which is what keeps prefix caching alive", () => {
		const original = [user("old"), assistant("older"), user("recent")];
		expect(JSON.stringify(applyFold(original, fold))).toBe(JSON.stringify(applyFold(original, fold)));
	});

	test("omits the instruction message entirely when nothing was pinned", () => {
		const bare = { ...fold, pinned: [] };
		const applied = applyFold([user("a"), assistant("b"), user("c")], bare);
		expect(syntheticCount(bare)).toBe(1);
		expect(applied[0].role).toBe("compactionSummary");
		expect(applied[1].role).toBe("user");
		expect(messageText(applied[1])).toBe("c");
	});

	test("pinned instructions are framed as a record, not a new request", () => {
		// Codex re-injects bare user messages because its model is trained on that shape. Pi's
		// is not, so without this framing a replayed instruction reads as something to answer.
		const text = pinnedInstructionsText(["do the thing"]);
		expect(text.startsWith(PINNED_PREFIX)).toBe(true);
		expect(text).toContain("not a new request");
		expect(text).toContain("<user-instruction>\ndo the thing\n</user-instruction>");
	});
});

describe("isFoldValid", () => {
	const original = [user("a", 10), assistant("b"), user("c", 12)];
	const fold: FoldState = {
		cutIndex: 2,
		summary: "s",
		pinned: [],
		tokensBefore: 1,
		timestamp: 0,
		originalLength: 3,
		headFingerprint: fingerprint(original[0]),
		boundaryFingerprint: fingerprint(original[1]),
	};

	test("holds while the history it was computed from is intact", () => {
		expect(isFoldValid(original, fold)).toBe(true);
		expect(isFoldValid([...original, assistant("d")], fold)).toBe(true);
	});

	test("a rewritten head invalidates it", () => {
		// Pi's own between-runs compaction replaces the head and renumbers everything.
		const compacted = [{ role: "compactionSummary", summary: "pi did this" }, user("c", 12), assistant("d")];
		expect(isFoldValid(compacted, fold)).toBe(false);
	});

	test("a rewritten boundary of the same length still invalidates it", () => {
		// Length alone would not catch this; the fingerprint compares content.
		const swapped = [original[0], assistant("DIFFERENT"), original[2]];
		expect(isFoldValid(swapped, fold)).toBe(false);
	});

	test("a fold with no tail left is invalid, never sent as a summary on its own", () => {
		expect(isFoldValid(original.slice(0, 2), fold)).toBe(false);
	});
});

describe("planFold", () => {
	test("folds the old prefix and pins the instructions inside it", () => {
		const original = [user("objective: ship it"), assistant(filler(200)), user(filler(60)), assistant(filler(60))];
		const plan = planFold(original, null, 300, settings, metrics);
		expect(plan).not.toBeNull();
		expect(plan?.cutIndex).toBeGreaterThan(0);
		expect(plan?.prefix.length).toBe(plan?.cutIndex);
		expect(plan?.pinned).toContain("objective: ship it");
		expect(plan?.saving).toBeGreaterThan(0);
	});

	test("refuses a fold that would not save enough to pay for a summarization call", () => {
		const original = [user(filler(2)), assistant(filler(2)), user(filler(200))];
		expect(planFold(original, null, 300, { ...settings, minSavingTokens: 1000 }, metrics)).toBeNull();
	});

	test("only the new material is summarized once a fold already exists", () => {
		// The existing summary is carried forward through generateSummary's previousSummary
		// argument instead, so already-summarized text is not put through a second pass.
		const original = [
			user("oldest"),
			assistant(filler(100)),
			user("middle instruction"),
			assistant(filler(100)),
			user(filler(60)),
			assistant(filler(60)),
		];
		const first = planFold(original, null, 400, settings, metrics);
		expect(first).not.toBeNull();
		const fold: FoldState = {
			cutIndex: first!.cutIndex,
			summary: "round one",
			pinned: first!.pinned,
			tokensBefore: 400,
			timestamp: 0,
			originalLength: original.length,
			headFingerprint: fingerprint(original[0]),
			boundaryFingerprint: fingerprint(original[first!.cutIndex - 1]),
		};
		const grown = [...original, assistant(filler(200)), user(filler(60)), assistant(filler(60))];
		const second = planFold(grown, fold, 600, settings, metrics);
		expect(second).not.toBeNull();
		expect(second!.cutIndex).toBeGreaterThan(fold.cutIndex);
		// The prefix starts where the previous fold ended, not at the beginning of history.
		expect(second!.prefix[0]).toBe(grown[fold.cutIndex]);
	});

	test("returns null rather than folding into its own summary", () => {
		const original = [user("a"), assistant("b"), user("c")];
		const fold: FoldState = {
			cutIndex: 2,
			summary: "s",
			pinned: [],
			tokensBefore: 1,
			timestamp: 0,
			originalLength: 3,
			headFingerprint: fingerprint(original[0]),
			boundaryFingerprint: fingerprint(original[1]),
		};
		// Nothing new has arrived, so there is nothing left to fold and the caller must fall
		// back rather than delete the summary it already paid for.
		expect(planFold(original, fold, 999_999, settings, metrics)).toBeNull();
	});

	test("never folds away the whole conversation", () => {
		const original = [user(filler(200)), assistant(filler(200))];
		const plan = planFold(original, null, 400, settings, metrics);
		if (plan) expect(plan.cutIndex).toBeLessThan(original.length);
	});
});

describe("looksLikeSizeError", () => {
	test("recognises the provider wordings that mean the prefix was too big", () => {
		// Mirrors pi-ai's OVERFLOW_PATTERNS. Codex branches on a typed ContextWindowExceeded
		// instead; Pi throws a plain Error, so the distinction has to come from the message.
		expect(looksLikeSizeError(new Error("prompt is too long: 300000 tokens"))).toBe(true);
		expect(looksLikeSizeError(new Error("This model's maximum context length is 272000 tokens"))).toBe(true);
		expect(looksLikeSizeError(new Error("Please reduce the length of the messages"))).toBe(true);
		expect(looksLikeSizeError(new Error("context_length_exceeded"))).toBe(true);
	});

	test("a rate limit is never treated as a size error", () => {
		// This is the whole point of the check: trimming spends the budget on a fault that
		// shrinking cannot fix, and "too many requests" would otherwise match "too many tokens".
		expect(looksLikeSizeError(new Error("429 rate limit exceeded, retry later"))).toBe(false);
		expect(looksLikeSizeError(new Error("Too Many Requests"))).toBe(false);
		expect(looksLikeSizeError(new Error("Throttling error: slow down"))).toBe(false);
	});

	test("unrelated faults do not trigger trimming", () => {
		expect(looksLikeSizeError(new Error("socket hang up"))).toBe(false);
		expect(looksLikeSizeError(new Error("401 unauthorized"))).toBe(false);
		expect(looksLikeSizeError(undefined)).toBe(false);
		expect(looksLikeSizeError(new Error(""))).toBe(false);
	});
});

describe("findLatestCut", () => {
	test("folds up to the newest valid boundary", () => {
		const messages = [user("a"), assistant("b"), toolResult("c")];
		// Not index 2: a tail may not begin with a tool result.
		expect(findLatestCut(messages)).toBe(1);
	});

	test("respects the synthetic head", () => {
		expect(findLatestCut([{ role: "compactionSummary", summary: "s" }, toolResult("x")], 1)).toBe(1);
	});
});

describe("planFoldUnderPressure", () => {
	test("uses the normal fold when the normal fold works", () => {
		const original = [user("obj"), assistant(filler(200)), user(filler(60)), assistant(filler(60))];
		const plan = planFoldUnderPressure(original, null, 400, settings, metrics, 300);
		expect(plan?.rung).toBe(1);
	});

	test("folds when no boundary sits after the point the budget ran out", () => {
		// The narrow case this exists for. The recent budget is used up inside a trailing tool
		// result, and a tail may not begin with one, so there is no valid cut at or after that
		// point. Pi's findCutPoint answers "keep everything" — right for Pi, whose compaction is
		// destructive, but it leaves the request oversized here. The last rung takes the newest
		// valid boundary instead, which is a step toward Codex, who keeps no tail at all.
		const original = [user("the objective"), assistant(filler(50)), toolResult(filler(5000))];
		expect(findFoldCut(original, settings.keepRecentTokens, metrics)).toBe(0);
		expect(planFold(original, null, 6000, settings, metrics)).toBeNull();

		const pressured = planFoldUnderPressure(original, null, 6000, settings, metrics, 5000);
		expect(pressured).not.toBeNull();
		expect(pressured?.rung).toBe("latest");
		expect(pressured?.cutIndex).toBe(1);
		// The instruction that was folded away is still carried verbatim.
		expect(pressured?.pinned).toContain("the objective");
	});

	test("cannot rescue an oversized final message, and does not pretend to", () => {
		// Nothing can fold away the message the model still needs. Codex survives this by
		// truncating the user message into its 20k verbatim budget; here the tail is kept whole,
		// so the honest answer is no fold and Pi's own overflow recovery takes over.
		expect(planFoldUnderPressure([user(filler(5000))], null, 5000, settings, metrics, 5000)).toBeNull();
	});

	test("waives the saving threshold only under pressure", () => {
		// minSavingTokens exists to avoid paying for a pointless summarization; once the request
		// will not fit, any saving is worth paying for.
		const tight = { ...settings, minSavingTokens: 1_000_000 };
		const original = [user("objective"), assistant(filler(50)), user(filler(5000)), assistant(filler(50))];
		expect(planFold(original, null, 6000, tight, metrics)).toBeNull();
		expect(planFoldUnderPressure(original, null, 6000, tight, metrics, 5000)).not.toBeNull();
	});

	test("still never folds away the whole conversation", () => {
		const original = [user(filler(5000)), assistant(filler(5000))];
		const plan = planFoldUnderPressure(original, null, 10_000, settings, metrics, 5000);
		if (plan) expect(plan.cutIndex).toBeLessThan(original.length);
	});

	test("returns null when there is genuinely nothing to fold", () => {
		expect(planFoldUnderPressure([user("only one")], null, 10, settings, metrics, 5)).toBeNull();
	});

	test("does not sacrifice the tail merely because the conversation is small", () => {
		// The bug this guard exists for, caught in verification rather than review. Under a low
		// trigger the whole conversation fits keepRecentTokens, so the normal fold finds nothing —
		// but the tail is not the problem, and folding it away left the model rediscovering its
		// task from the summary on every single call. A run doing that can loop.
		const original = [user("the objective"), assistant(filler(50)), toolResult(filler(100))];
		expect(planFold(original, null, 5000, settings, metrics)).toBeNull();
		// Measured size is over the trigger (overhead and real usage push it there) but what a
		// full-budget fold would keep is not, so pressure must stay out of it.
		expect(planFoldUnderPressure(original, null, 5000, settings, metrics, 5000)).toBeNull();
	});

	test("pressure is off unless a trigger is supplied", () => {
		const original = [user("the objective"), assistant(filler(50)), toolResult(filler(5000))];
		expect(planFoldUnderPressure(original, null, 6000, settings, metrics)).toBeNull();
	});
});

describe("dropOldest", () => {
	test("drops roughly the requested fraction and resumes at a clean boundary", () => {
		const prefix = [user(filler(40)), assistant(filler(40)), toolResult(filler(40)), assistant(filler(40))];
		const trimmed = dropOldest(prefix, 0.25, metrics);
		expect(trimmed.length).toBeLessThan(prefix.length);
		expect(isCutPoint(trimmed[0])).toBe(true);
	});

	test("always leaves something to summarize", () => {
		expect(dropOldest([user("only")], 0.9, metrics)).toHaveLength(1);
		expect(dropOldest([], 0.9, metrics)).toHaveLength(0);
		expect(dropOldest([user(filler(10)), assistant(filler(10))], 1, metrics).length).toBeGreaterThan(0);
	});
});

describe("messageText", () => {
	test("reads the shapes Pi actually produces", () => {
		expect(messageText(user("plain"))).toBe("plain");
		expect(messageText({ role: "user", content: "string form" })).toBe("string form");
		expect(messageText({ role: "compactionSummary", summary: "the summary" })).toBe("the summary");
		expect(
			messageText({
				role: "assistant",
				content: [{ type: "thinking", thinking: "hmm" }, { type: "toolCall", name: "bash" }],
			}),
		).toBe("hmm\nbash");
	});

	test("survives missing and malformed content", () => {
		expect(messageText(undefined)).toBe("");
		expect(messageText({ role: "user" })).toBe("");
		expect(messageText({ role: "user", content: [null, 5, { type: "image" }] as unknown })).toBe("");
	});
});

describe("config", () => {
	test("defaults mirror Codex's own numbers", () => {
		// 90% trigger (openai_models.rs:310) and a 20k verbatim user-message budget
		// (COMPACT_USER_MESSAGE_MAX_TOKENS).
		expect(DEFAULT_FOLD_CONFIG.triggerPercent).toBe(0.9);
		expect(DEFAULT_FOLD_CONFIG.pinUserTokens).toBe(20_000);
		expect(DEFAULT_FOLD_CONFIG.keepRecentTokens).toBe(20_000);
		expect(DEFAULT_FOLD_CONFIG.enabled).toBe(true);
	});

	test("a missing config file is not an error", () => {
		const previous = process.env.PI_CODING_AGENT_DIR;
		process.env.PI_CODING_AGENT_DIR = "/nonexistent-pi-dir-for-tests";
		try {
			const loaded = loadExtensionConfig();
			expect(loaded.warnings).toEqual([]);
			expect(loaded.config.fold).toEqual(DEFAULT_FOLD_CONFIG);
		} finally {
			if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
			else process.env.PI_CODING_AGENT_DIR = previous;
		}
	});

	test("top-level enabled: false disables the fold too", () => {
		// Pre-merge this key turned the whole extension off; the fold must honor it
		// whether the fold config comes from the unified file, a legacy file, or defaults.
		withAgentDir({ "pi-context-handoff.json": { enabled: false } }, () => {
			const loaded = loadExtensionConfig();
			expect(loaded.config.handoff.enabled).toBe(false);
			expect(loaded.config.fold.enabled).toBe(false);
		});
		withAgentDir(
			{
				"pi-context-handoff.json": { enabled: false },
				"pi-codex-compaction.json": { triggerPercent: 0.8 },
			},
			() => {
				const loaded = loadExtensionConfig();
				expect(loaded.config.fold.enabled).toBe(false);
				expect(loaded.config.fold.triggerPercent).toBe(0.8);
			},
		);
		// A leftover legacy {"enabled": true} must not re-enable the fold against the
		// top-level kill switch; only the unified file's fold.enabled may.
		withAgentDir(
			{
				"pi-context-handoff.json": { enabled: false },
				"pi-codex-compaction.json": { enabled: true },
			},
			() => {
				const loaded = loadExtensionConfig();
				expect(loaded.config.handoff.enabled).toBe(false);
				expect(loaded.config.fold.enabled).toBe(false);
			},
		);
		// An explicit fold.enabled can still turn just the fold back on.
		withAgentDir(
			{ "pi-context-handoff.json": { enabled: false, fold: { enabled: true } } },
			() => {
				const loaded = loadExtensionConfig();
				expect(loaded.config.handoff.enabled).toBe(false);
				expect(loaded.config.fold.enabled).toBe(true);
			},
		);
	});

	test("fold: false is a kill switch for the fold alone", () => {
		withAgentDir({ "pi-context-handoff.json": { enabled: true, fold: false } }, () => {
			const loaded = loadExtensionConfig();
			expect(loaded.config.handoff.enabled).toBe(true);
			expect(loaded.config.fold.enabled).toBe(false);
		});
	});

	test("a legacy pi-codex-compaction.json still configures the fold", () => {
		withAgentDir(
			{
				"pi-context-handoff.json": { focus: "handoff note" },
				"pi-codex-compaction.json": { keepRecentTokens: 5000, notify: false },
			},
			() => {
				const loaded = loadExtensionConfig();
				expect(loaded.config.handoff.focus).toBe("handoff note");
				expect(loaded.config.fold.keepRecentTokens).toBe(5000);
				expect(loaded.config.fold.notify).toBe(false);
			},
		);
		// ...but a unified fold object wins over the legacy file.
		withAgentDir(
			{
				"pi-context-handoff.json": { fold: { keepRecentTokens: 9000 } },
				"pi-codex-compaction.json": { keepRecentTokens: 5000 },
			},
			() => {
				expect(loadExtensionConfig().config.fold.keepRecentTokens).toBe(9000);
			},
		);
	});
});

describe("instructions", () => {
	test("the focus tells the summarizer the work is mid-flight", () => {
		const focus = buildFoldFocus({ pinned: false });
		expect(focus).toContain("still in progress");
		expect(focus).toContain("in flight");
		// Prompt-injection hygiene: tool output and fetched pages are data, not instructions.
		expect(focus).toContain("untrusted data");
	});

	test("mentions the verbatim copy only when there is one", () => {
		expect(buildFoldFocus({ pinned: true })).toContain("verbatim");
		expect(buildFoldFocus({ pinned: false })).not.toContain("reproduced verbatim in a separate message");
	});

	test("operator focus is appended, never dropped", () => {
		expect(buildFoldFocus({ pinned: false, extra: "watch the migration" })).toContain("watch the migration");
	});
});
