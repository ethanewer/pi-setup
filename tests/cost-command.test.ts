import { describe, expect, test } from "bun:test";
import { catalogRateLabel, costTable, rateLabel, tierNote } from "../forks/pi-cost/extensions/cost/rates.js";

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

describe("tierNote", () => {
	test("names the peak pair when overrides differ from base", () => {
		const pricing = {
			prompt: "0.00000015",
			completion: "0.0000006",
			overrides: [
				{ prompt: "0.0000003", completion: "0.0000012" },
				{ prompt: "0.00000015", completion: "0.0000006" },
			],
		};
		expect(tierNote(pricing)).toBe("peak windows up to $0.30 in / $1.20 out");
	});

	test("is empty when overrides only repeat the base rates", () => {
		const pricing = {
			prompt: "0.00000015",
			completion: "0.0000006",
			overrides: [{ prompt: "0.00000015", completion: "0.0000006" }],
		};
		expect(tierNote(pricing)).toBe("");
	});

	test("is empty without overrides", () => {
		expect(tierNote({ prompt: "0.00000015", completion: "0.0000006" })).toBe("");
		expect(tierNote({ prompt: "0.00000015", completion: "0.0000006", overrides: [] })).toBe("");
	});
});

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
		{
			id: "deepseek/deepseek-v4.1-flash",
			pricing: {
				prompt: "0.00000015",
				completion: "0.0000006",
				input_cache_read: "0.000000003",
				overrides: [{ prompt: "0.0000003", completion: "0.0000012" }],
			},
		},
	];

	test("one aligned row per pinned model, tier note on its own line", () => {
		const models = [
			{ id: "z-ai/glm-5.3" },
			{ id: "deepseek/deepseek-v4.1-flash" },
		];
		const out = costTable(models, openrouter);
		const lines = out.split("\n");
		expect(lines).toHaveLength(3);
		expect(lines[0]).toContain("z-ai/glm-5.3");
		expect(lines[0]).toContain("$1.40 in / $4.40 out / $0.26 cache read");
		expect(lines[1]).toContain("deepseek/deepseek-v4.1-flash");
		expect(lines[1]).toContain("$0.15 in / $0.60 out / $0.003 cache read");
		expect(lines[2]).toContain("peak windows up to $0.30 in / $1.20 out");
		// Aligned: the rate text of both rows starts at the same column.
		const idWidth = Math.max(...models.map((m) => m.id.length));
		expect(lines[0].indexOf("$1.40")).toBe(`  ${"z-ai/glm-5.3".padEnd(idWidth)}  `.length);
		expect(lines[1].indexOf("$0.15")).toBe(lines[0].indexOf("$1.40"));
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