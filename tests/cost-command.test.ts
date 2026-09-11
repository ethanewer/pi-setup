import { describe, expect, test } from "bun:test";
import { catalogRateLabel, costTable, effectivePricing, rateLabel } from "../forks/pi-cost/extensions/cost/rates.js";

// The real V4.1 Flash pricing from OpenRouter: off-peak on weekends all day and
// on weekdays outside the peak windows (01:00–04:00 and 06:00–10:00 UTC).
const V41_PRICING = {
	prompt: "0.00000015",
	completion: "0.0000006",
	input_cache_read: "0.000000003",
	overrides: [
		{ utc_days: ["saturday", "sunday"], prompt: "0.00000015", completion: "0.0000006", input_cache_read: "0.000000003" },
		{ utc_days: ["monday", "tuesday", "wednesday", "thursday", "friday"], utc_start: 0, utc_end: 100, prompt: "0.00000015", completion: "0.0000006", input_cache_read: "0.000000003" },
		{ utc_days: ["monday", "tuesday", "wednesday", "thursday", "friday"], utc_start: 100, utc_end: 400, prompt: "0.0000003", completion: "0.0000012", input_cache_read: "0.000000006" },
		{ utc_days: ["monday", "tuesday", "wednesday", "thursday", "friday"], utc_start: 400, utc_end: 600, prompt: "0.00000015", completion: "0.0000006", input_cache_read: "0.000000003" },
		{ utc_days: ["monday", "tuesday", "wednesday", "thursday", "friday"], utc_start: 600, utc_end: 1000, prompt: "0.0000003", completion: "0.0000012", input_cache_read: "0.000000006" },
		{ utc_days: ["monday", "tuesday", "wednesday", "thursday", "friday"], utc_start: 1000, utc_end: 0, prompt: "0.00000015", completion: "0.0000006", input_cache_read: "0.000000003" },
	],
};

/** A Wednesday at the given UTC time. 2026-09-09 was a Wednesday. */
function wed(hhmm: string): Date {
	const [h, m] = hhmm.split(":").map(Number);
	return new Date(Date.UTC(2026, 8, 9, h, m));
}

function sat(hhmm: string): Date {
	const [h, m] = hhmm.split(":").map(Number);
	return new Date(Date.UTC(2026, 8, 12, h, m)); // a Saturday
}

describe("rateLabel", () => {
	test("converts per-token strings to $/Mtok", () => {
		expect(rateLabel({ prompt: "0.00000015", completion: "0.0000006", input_cache_read: "0.000000003" })).toBe(
			"$0.15 in / $0.60 out / $0.003 cache read",
		);
	});

	test("shows cache write before cache read when charged", () => {
		expect(
			rateLabel({ prompt: "0.000002", completion: "0.000006", input_cache_read: "0.00000025", input_cache_write: "0.0000025" }),
		).toBe("$2.00 in / $6.00 out / $2.50 cache write / $0.25 cache read");
	});

	test("omits zero and missing components", () => {
		expect(rateLabel({ prompt: "0", completion: "0.0000001" })).toBe("$0.10 out");
		expect(rateLabel({ prompt: null, completion: "0.0000001", input_cache_read: "0" })).toBe("$0.10 out");
	});

	test("is empty for an unpriced model", () => {
		expect(rateLabel({})).toBe("");
		expect(rateLabel({ prompt: "0", completion: "0" })).toBe("");
	});
});

describe("effectivePricing", () => {
	test("off-peak on a weekend, any hour", () => {
		for (const t of ["00:00", "09:30", "23:59"]) {
			expect(effectivePricing(V41_PRICING, sat(t)).prompt).toBe("0.00000015");
		}
	});

	test("peak windows on weekdays: 01:00–04:00 and 06:00–10:00 UTC", () => {
		for (const t of ["01:00", "02:30", "03:59", "06:00", "09:59"]) {
			const effective = effectivePricing(V41_PRICING, wed(t));
			expect(effective.prompt).toBe("0.0000003");
			expect(effective.completion).toBe("0.0000012");
		}
	});

	test("off-peak outside the peak windows", () => {
		for (const t of ["00:00", "00:59", "04:00", "05:00", "10:00", "16:00", "23:59"]) {
			expect(effectivePricing(V41_PRICING, wed(t)).prompt).toBe("0.00000015");
		}
	});

	test("an override replaces only the fields it carries", () => {
		// Peak window: cache read doubles along with the rest.
		const peak = effectivePricing(V41_PRICING, wed("02:00"));
		expect(peak.input_cache_read).toBe("0.000000006");
		// Base fields the override does not name (none here, but the merge is
		// still field-wise) survive.
		const partial = { prompt: "0.0000001", overrides: [{ utc_days: ["wednesday"], utc_start: 0, utc_end: 1, completion: "0.0000009" }] };
		const effective = effectivePricing(partial, wed("00:00"));
		expect(effective.prompt).toBe("0.0000001");
		expect(effective.completion).toBe("0.0000009");
	});

	test("no matching override leaves the base rates", () => {
		const pricing = {
			prompt: "0.00000015",
			completion: "0.0000006",
			overrides: [{ utc_days: ["saturday", "sunday"], prompt: "0.0000009" }],
		};
		expect(effectivePricing(pricing, wed("12:00")).prompt).toBe("0.00000015");
	});

	test("models without overrides pass through untouched", () => {
		const pricing = { prompt: "0.0000014", completion: "0.0000044" };
		expect(effectivePricing(pricing, wed("02:00"))).toBe(pricing);
		expect(effectivePricing({ prompt: "0.0000014", overrides: [] }, wed("12:00")).prompt).toBe("0.0000014");
	});

	test("utc_end: 0 means through end of day, and windows may wrap midnight", () => {
		const toEndOfDay = { prompt: "0.0000009", overrides: [{ utc_days: ["friday"], utc_start: 1000, utc_end: 0, prompt: "0.0000005" }] };
		expect(effectivePricing(toEndOfDay, fri("17:00")).prompt).toBe("0.0000005"); // 1700 UTC Friday
		expect(effectivePricing(toEndOfDay, fri("09:59")).prompt).toBe("0.0000009"); // before the window
		const wrap = { prompt: "0.0000009", overrides: [{ utc_days: ["wednesday", "thursday"], utc_start: 1200, utc_end: 60, prompt: "0.0000005" }] };
		expect(effectivePricing(wrap, wed("23:30")).prompt).toBe("0.0000005"); // wraps into Thursday
		expect(effectivePricing(wrap, new Date(Date.UTC(2026, 8, 10, 0, 30))).prompt).toBe("0.0000005"); // Thursday 00:30
		expect(effectivePricing(wrap, wed("10:00")).prompt).toBe("0.0000009"); // outside the wrapped window
	});
});

/** A Friday at the given UTC time. 2026-09-11 was a Friday. */
function fri(hhmm: string): Date {
	const [h, m] = hhmm.split(":").map(Number);
	return new Date(Date.UTC(2026, 8, 11, h, m));
}

describe("catalogRateLabel", () => {
	test("formats per-Mtok numbers", () => {
		expect(catalogRateLabel({ input: 0.14, output: 0.28, cacheRead: 0.0028 })).toBe(
			"$0.14 in / $0.28 out / $0.003 cache read",
		);
	});
});

describe("costTable", () => {
	const openrouter = [
		{
			id: "z-ai/glm-5.3",
			pricing: { prompt: "0.0000014", completion: "0.0000044", input_cache_read: "0.00000026" },
		},
		{ id: "deepseek/deepseek-v4.1-flash", pricing: V41_PRICING },
	];

	test("one line per pinned model at the rates in force at `now`", () => {
		const models = [{ id: "z-ai/glm-5.3" }, { id: "deepseek/deepseek-v4.1-flash" }];
		const peak = costTable(models, openrouter, wed("02:00"));
		const peakLines = peak.split("\n");
		expect(peakLines).toHaveLength(2);
		expect(peakLines[0]).toContain("$1.40 in / $4.40 out / $0.26 cache read");
		expect(peakLines[1]).toContain("$0.30 in / $1.20 out / $0.006 cache read");
		// Aligned: the rate text of both rows starts at the same column.
		const idWidth = Math.max(...models.map((m) => m.id.length));
		expect(peakLines[0].indexOf("$1.40")).toBe(`  ${"z-ai/glm-5.3".padEnd(idWidth)}  `.length);
		expect(peakLines[1].indexOf("$0.30")).toBe(peakLines[0].indexOf("$1.40"));

		const offPeak = costTable(models, openrouter, wed("05:00"));
		expect(offPeak.split("\n")[1]).toContain("$0.15 in / $0.60 out / $0.003 cache read");
		const weekend = costTable(models, openrouter, sat("12:00"));
		expect(weekend.split("\n")[1]).toContain("$0.15 in / $0.60 out / $0.003 cache read");
	});

	test("falls back to catalog cost when the model is missing from the fetched list", () => {
		const out = costTable([{ id: "qwen/qwen3.8-flash", cost: { input: 0.15, output: 0.47, cacheRead: 0.016 } }], openrouter);
		expect(out).toContain("$0.15 in / $0.47 out / $0.02 cache read (catalog)");
	});

	test("marks an unpriced model when neither source has rates", () => {
		expect(costTable([{ id: "x/y" }], openrouter)).toContain("not priced");
	});

	test("empty catalog still renders catalog costs", () => {
		const out = costTable([{ id: "qwen/qwen3.8-flash", cost: { input: 0.15, output: 0.47 } }], undefined);
		expect(out).toContain("(catalog)");
	});
});