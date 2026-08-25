import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const patchPath = join(import.meta.dir, "..", "patches", "pi-ai@0.84.3-reasoning-details.patch");
const patch = readFileSync(patchPath, "utf8");

function loadNormalizer(): (details: Array<Record<string, unknown>>) => Array<Record<string, unknown>> {
	const additions = patch
		.split("\n")
		.filter((line) => line.startsWith("+") && !line.startsWith("+++"))
		.map((line) => line.slice(1))
		.join("\n");
	const helperSource = additions.match(
		/function fillMissingCommonReasoningDetailFields[\s\S]*?function normalizeOpenAIReasoningDetails[\s\S]*?\n}/,
	)?.[0];
	if (!helperSource) throw new Error("Reasoning normalizer was not found in the Pi AI patch");
	return new Function(`${helperSource}\nreturn normalizeOpenAIReasoningDetails;`)() as ReturnType<typeof loadNormalizer>;
}

test("Pi AI patch merges adjacent historical reasoning deltas without crossing opaque blocks", () => {
	const normalize = loadNormalizer();
	const encrypted = { type: "reasoning.encrypted", id: "opaque", data: "ciphertext" };
	const normalized = normalize([
		{ type: "reasoning.text", text: "The", index: 0 },
		{ type: "reasoning.text", text: " answer", signature: "signed", format: "openai-responses-v1" },
		{ type: "reasoning.summary", summary: "Looked" },
		{ type: "reasoning.summary", summary: " it up", index: 1 },
		encrypted,
		{ type: "reasoning.text", text: "After" },
		{ type: "reasoning.text", text: " opaque" },
	]);

	expect(normalized).toEqual([
		{
			type: "reasoning.text",
			text: "The answer",
			index: 0,
			signature: "signed",
			format: "openai-responses-v1",
		},
		{ type: "reasoning.summary", summary: "Looked it up", index: 1 },
		encrypted,
		{ type: "reasoning.text", text: "After opaque" },
	]);
});

test("Pi AI patch normalizes both new streams and replayed stored signatures", () => {
	expect(patch).toContain("appendOpenAIReasoningDetail(preservedDetails, detail)");
	expect(patch).toContain("? normalizeOpenAIReasoningDetails(parsed)");
	expect(patch).toContain("details.push({ ...detail })");
});
