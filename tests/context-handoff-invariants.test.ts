import { describe, expect, test } from "bun:test";

/**
 * Invariant tests for pi-context-handoff's fold half.
 *
 * The failure these guard: any second package loaded next to pi-context-handoff that also
 * handles `context` (as a once-separate fold package did, before the merge) puts two handlers on
 * one request. Pi's emitContext feeds each handler the previous handler's output, so the
 * second sees the folded list with trustUsageFrom = 0, trusts the pre-fold usage still
 * sitting in the kept tail, and folds again immediately — a summary of a summary. These
 * tests pin the conditions that make that impossible.
 *
 * Pure logic only: no Pi import, so the suite still runs with nothing installed.
 */

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const FORKS = join(__dirname, "..", "forks");
const HANDOFF = join(FORKS, "pi-context-handoff", "extensions", "context-handoff");

describe("merge invariants", () => {
	test("the merged extension registers exactly one context handler", () => {
		const source = readFileSync(join(HANDOFF, "index.ts"), "utf8") + readFileSync(join(HANDOFF, "fold-hook.ts"), "utf8");
		const registrations = source.match(/pi\.on\("context"/g) ?? [];
		expect(registrations.length).toBe(1);
	});

	test("the fold keeps its session-entry type and test seam", () => {
		const source = readFileSync(join(HANDOFF, "fold-hook.ts"), "utf8");
		expect(source).toContain('FOLD_ENTRY_TYPE = "context-handoff-fold"');
		expect(source).toContain('FORCE_TRIGGER_ENV = "PI_CONTEXT_HANDOFF_FORCE_TRIGGER_TOKENS"');
		const resume = readFileSync(join(HANDOFF, "resume.ts"), "utf8");
		expect(resume).toContain('RESUME_MESSAGE_TYPE = "context-handoff-resume"');
	});

	test("no fork other than pi-context-handoff registers a context handler", () => {
		// Any other fork adding a `context` handler would chain-fold on the same request.
		const install = readFileSync(join(__dirname, "..", "install.sh"), "utf8");
		const forksLine = install.match(/^FORKS="([^"]+)"/m);
		expect(forksLine).not.toBeNull();
		const forks = forksLine![1].split(/\s+/).filter((f) => f !== "pi-context-handoff");
		for (const fork of forks) {
			const dir = join(FORKS, fork, "extensions");
			let found: string[] = [];
			const walk = (d: string) => {
				for (const entry of readdirSync(d, { withFileTypes: true })) {
					const p = join(d, entry.name);
					if (entry.isDirectory()) walk(p);
					else if (entry.name.endsWith(".ts") && readFileSync(p, "utf8").includes('on("context"')) found.push(p);
				}
			};
			try { walk(dir); } catch { /* fork without an extensions dir */ }
			expect(found, `${fork} registers a context handler: ${found.join(", ")}`).toEqual([]);
		}
	});

	test("the merged extension has the fold modules", () => {
		const files = readdirSync(HANDOFF);
		for (const expected of ["fold.ts", "fold-hook.ts", "config.ts", "util.ts"]) {
			expect(files).toContain(expected);
		}
	});
});
