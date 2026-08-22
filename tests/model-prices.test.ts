import { describe, expect, test } from "bun:test";

import { badgeLabel, formatCost, rateParts, tierLines } from "../forks/pi-model-prices/extensions/model-prices/pricing.js";

describe("formatCost", () => {
	test("keeps two decimals by convention", () => {
		expect(formatCost(1.4)).toBe("1.40");
		expect(formatCost(4.4)).toBe("4.40");
		expect(formatCost(0.26)).toBe("0.26");
		expect(formatCost(5)).toBe("5.00");
	});

	test("keeps a third decimal when it is significant", () => {
		// DeepSeek's cache-read rate would round away at two decimals.
		expect(formatCost(0.016)).toBe("0.016");
		expect(formatCost(1.188)).toBe("1.188");
		expect(formatCost(3.564)).toBe("3.564");
	});

	test("drops a trailing zero only beyond two decimals", () => {
		expect(formatCost(6.25)).toBe("6.25");
		expect(formatCost(12.5)).toBe("12.50");
	});

	test("guards non-finite input", () => {
		expect(formatCost(Number.NaN)).toBe("?");
	});
});

describe("rateParts", () => {
	test("orders in, out, cache write, cache read", () => {
		expect(rateParts({ input: 0.2, output: 1.2, cacheRead: 0.02, cacheWrite: 0.25 })).toEqual([
			"$0.20 in",
			"$1.20 out",
			"$0.25 cache write",
			"$0.02 cache read",
		]);
	});

	test("omits zero components", () => {
		expect(rateParts({ input: 1.4, output: 4.4, cacheRead: 0.26, cacheWrite: 0 })).toEqual([
			"$1.40 in",
			"$4.40 out",
			"$0.26 cache read",
		]);
	});

	test("handles a missing cost object", () => {
		expect(rateParts(undefined)).toEqual([]);
	});
});

describe("badgeLabel", () => {
	test("joins rate parts with commas", () => {
		expect(badgeLabel({ input: 1.4, output: 4.4, cacheRead: 0.26, cacheWrite: 0 }, false)).toBe(
			"$1.40 in, $4.40 out, $0.26 cache read",
		);
	});

	test("a subscription replaces rates entirely", () => {
		expect(badgeLabel({ input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 }, true)).toBe("sub");
	});

	test("an unpriced model on an API key is empty", () => {
		expect(badgeLabel({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, false)).toBe("");
		expect(badgeLabel(undefined, false)).toBe("");
	});
});

describe("tierLines", () => {
	test("describes each tier with whole-request semantics", () => {
		expect(
			tierLines([{ inputTokensAbove: 272000, input: 10, output: 45, cacheRead: 1, cacheWrite: 12.5 }]),
		).toEqual(["long-context rates above 272k input tokens (whole request): $10.00 in, $45.00 out, $12.50 cache write, $1.00 cache read"]);
	});

	test("sorts tiers by threshold and returns nothing without tiers", () => {
		expect(
			tierLines([
				{ inputTokensAbove: 544000, input: 20, output: 90, cacheRead: 2, cacheWrite: 25 },
				{ inputTokensAbove: 272000, input: 10, output: 45, cacheRead: 1, cacheWrite: 12.5 },
			])[0],
		).toContain("above 272k");
		expect(tierLines(undefined)).toEqual([]);
		expect(tierLines([])).toEqual([]);
	});
});
