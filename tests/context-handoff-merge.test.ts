import { describe, expect, test } from "bun:test";

/**
 * Merge regression tests for the pi-context-handoff / pi-codex-compaction unification.
 *
 * The failure these guard: the standalone pi-codex-compaction package loaded next to the
 * merged pi-context-handoff puts two `context` handlers on one request. Pi's emitContext
 * feeds each handler the previous handler's output, so the standalone sees the folded
 * list with trustUsageFrom = 0, trusts the pre-fold usage still sitting in the kept tail,
 * and folds again immediately — a summary of a summary. These tests pin the conditions
 * that make that impossible.
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
		// The report tooling and any external monitors count on these names.
		const source = readFileSync(join(HANDOFF, "fold-hook.ts"), "utf8");
		expect(source).toContain('FOLD_ENTRY_TYPE = "codex-compaction-fold"');
		expect(source).toContain('FORCE_TRIGGER_ENV = "PI_CODEX_COMPACTION_FORCE_TRIGGER_TOKENS"');
		const resume = readFileSync(join(HANDOFF, "resume.ts"), "utf8");
		expect(resume).toContain('RESUME_MESSAGE_TYPE = "context-handoff-resume"');
	});

	test("the standalone pi-codex-compaction fork no longer ships a package manifest", () => {
		// install.sh installs every fork listed in FORKS; the standalone fold must not be
		// among them or both handlers end up live on one request. The fork directory may
		// remain on disk for history, but nothing may reference it as an install source.
		const install = readFileSync(join(__dirname, "..", "install.sh"), "utf8");
		const forksLine = install.match(/^FORKS="([^"]+)"/m);
		expect(forksLine).not.toBeNull();
		expect(forksLine![1].split(/\s+/)).not.toContain("pi-codex-compaction");
		// The `p` wrapper template must not load it either.
		expect(install).not.toContain("local/pi-codex-compaction/extensions");
	});

	test("the merged extension has the fold modules", () => {
		const files = readdirSync(HANDOFF);
		for (const expected of ["fold.ts", "fold-hook.ts", "config.ts", "util.ts"]) {
			expect(files).toContain(expected);
		}
	});
});
