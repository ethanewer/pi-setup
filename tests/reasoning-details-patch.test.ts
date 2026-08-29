import { expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const patchPath = join(import.meta.dir, "..", "patches", "pi-ai@0.84.4-reasoning-details.patch");
const patch = readFileSync(patchPath, "utf8");

const installedPiAi = join(
	process.env.BUN_INSTALL ?? join(homedir(), ".bun"),
	"install",
	"global",
	"node_modules",
	"@earendil-works",
	"pi-ai",
	"dist",
	"api",
	"openai-completions.js",
);

test("patch routes historical replay through the normalizer", () => {
	expect(patch).toContain("? normalizeOpenAIReasoningDetails(parsed)");
	// The stream-concatenation half is upstream since 0.84.4; the patch must not
	// re-add the helpers it already ships (a later duplicate would silently win).
	expect(patch).not.toContain("function appendOpenAIReasoningDetail");
	expect(patch).not.toContain("function fillMissingCommonReasoningDetailFields");
});

test.skipIf(!existsSync(installedPiAi))(
	"installed pi-ai normalizes adjacent historical reasoning deltas without crossing opaque blocks",
	() => {
		const source = readFileSync(installedPiAi, "utf8");
		// Extract the real normalizer functions from the installed patched module
		// rather than restating the merge contract here.
		const pick = (name: string): string => {
			const match = source.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n}`));
			if (!match) throw new Error(`function ${name} not found in installed pi-ai`);
			return match[0];
		};
		const helperSource = [
			pick("fillMissingCommonReasoningDetailFields"),
			pick("appendOpenAIReasoningDetail"),
			pick("normalizeOpenAIReasoningDetails"),
		].join("\n");
		const normalize = new Function(`${helperSource}\nreturn normalizeOpenAIReasoningDetails;`)() as (
			details: Array<Record<string, unknown>>,
		) => Array<Record<string, unknown>>;

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
	},
);
