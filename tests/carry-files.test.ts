import { describe, expect, test } from "bun:test";

import {
	carryFileLists,
	formatFileLists,
	mergeFileLists,
	previousFileLists,
	stripFileLists,
} from "../forks/pi-context-handoff/extensions/context-handoff/carry-files";

/** Exactly the shape Pi's formatFileOperations produces. */
const block = (read: string[], mod: string[]) => {
	const s: string[] = [];
	if (read.length) s.push(`<read-files>\n${read.join("\n")}\n</read-files>`);
	if (mod.length) s.push(`<modified-files>\n${mod.join("\n")}\n</modified-files>`);
	return s.length ? `\n\n${s.join("\n\n")}` : "";
};

describe("format matches Pi's", () => {
	test("read only, modified only, both, neither", () => {
		expect(formatFileLists({ readFiles: ["a.ts"], modifiedFiles: [] })).toBe(block(["a.ts"], []));
		expect(formatFileLists({ readFiles: [], modifiedFiles: ["b.ts"] })).toBe(block([], ["b.ts"]));
		expect(formatFileLists({ readFiles: ["a.ts"], modifiedFiles: ["b.ts"] })).toBe(block(["a.ts"], ["b.ts"]));
		expect(formatFileLists({ readFiles: [], modifiedFiles: [] })).toBe("");
	});
});

describe("merge", () => {
	test("unions both lists and sorts them", () => {
		expect(mergeFileLists({ readFiles: ["b"], modifiedFiles: [] }, { readFiles: ["a"], modifiedFiles: [] })).toEqual({
			readFiles: ["a", "b"],
			modifiedFiles: [],
		});
	});

	test("a file modified anywhere is never also listed as read, as in Pi", () => {
		expect(
			mergeFileLists({ readFiles: ["x.ts"], modifiedFiles: [] }, { readFiles: [], modifiedFiles: ["x.ts"] }),
		).toEqual({ readFiles: [], modifiedFiles: ["x.ts"] });
	});
});

describe("strip", () => {
	test("removes both blocks and leaves the prose", () => {
		const summary = `The brief.${block(["a.ts"], ["b.ts"])}`;
		expect(stripFileLists(summary)).toBe("The brief.");
	});

	test("leaves a summary that has no blocks alone", () => {
		expect(stripFileLists("Just prose.")).toBe("Just prose.");
	});

	test("does not eat prose that merely mentions the tag name", () => {
		expect(stripFileLists("We discussed <read-files> as a concept.")).toBe("We discussed <read-files> as a concept.");
	});
});

describe("carryFileLists", () => {
	const entries = [
		{ type: "message" },
		{ type: "compaction", details: { readFiles: ["old-read.ts"], modifiedFiles: ["old-mod.ts"] } },
		{ type: "message" },
	];

	test("carries the previous compaction's lists into the new summary", () => {
		const fresh = { summary: `Brief.${block(["new-read.ts"], [])}`, details: { readFiles: ["new-read.ts"], modifiedFiles: [] } };
		const out = carryFileLists(fresh, entries);
		expect(out.summary).toBe(`Brief.${block(["new-read.ts", "old-read.ts"], ["old-mod.ts"])}`);
		expect(out.details).toEqual({ readFiles: ["new-read.ts", "old-read.ts"], modifiedFiles: ["old-mod.ts"] });
	});

	test("is a no-op when there is nothing to carry", () => {
		const fresh = { summary: "Brief.", details: { readFiles: [], modifiedFiles: [] } };
		expect(carryFileLists(fresh, [{ type: "message" }])).toBe(fresh);
		expect(carryFileLists(fresh, [])).toBe(fresh);
		expect(carryFileLists(fresh, undefined)).toBe(fresh);
	});

	test("reads the most recent compaction, not the first", () => {
		const many = [
			{ type: "compaction", details: { readFiles: ["stale.ts"], modifiedFiles: [] } },
			{ type: "compaction", details: { readFiles: ["recent.ts"], modifiedFiles: [] } },
		];
		expect(previousFileLists(many).readFiles).toEqual(["recent.ts"]);
	});

	test("survives a malformed previous entry", () => {
		const junk = [{ type: "compaction", details: { readFiles: "not-an-array", modifiedFiles: [7, "ok.ts"] } }];
		expect(previousFileLists(junk)).toEqual({ readFiles: [], modifiedFiles: ["ok.ts"] });
	});

	test("keeps prose intact when the fresh summary carried no block", () => {
		const fresh = { summary: "Only prose.", details: {} };
		const out = carryFileLists(fresh, entries);
		expect(out.summary).toBe(`Only prose.${block(["old-read.ts"], ["old-mod.ts"])}`);
	});
});
