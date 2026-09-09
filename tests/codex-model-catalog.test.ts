import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const REPO = join(import.meta.dir, "..");

// The ocdx codex /model picker is driven by the managed catalog
// (model_catalog_json in the generated config.toml). Its slugs must stay in
// lockstep with the handles the occ/ocdx launchers offer, and every entry must
// default to high reasoning - the open-weight profiles' defining traits.

function handles(wrapper: string): string[] {
	const sh = readFileSync(join(REPO, "lib/wrappers", wrapper), "utf8");
	const match = sh.match(/^HANDLES="([^"]+)"$/m);
	if (!match) throw new Error(`HANDLES not found in ${wrapper}`);
	return match[1].split(" ");
}

function slugFor(wrapper: string): (handle: string) => string {
	const sh = readFileSync(join(REPO, "lib/wrappers", wrapper), "utf8");
	return (handle: string) => {
		const match = sh.match(new RegExp(`\\s{4}${handle}\\)\\s+printf '%s' "([^"]+)"`));
		if (!match) throw new Error(`no slug for ${handle} in ${wrapper}`);
		return match[1];
	};
}

test("the codex catalog covers exactly the pinned open-weight models, all defaulting to high", () => {
	const catalog = JSON.parse(readFileSync(join(REPO, "config/codex-model-catalog.json"), "utf8"));
	const ocdxSlug = slugFor("ocdx.sh");
	const expected = handles("ocdx.sh").map(ocdxSlug);
	expect(catalog.models.map((m: { slug: string }) => m.slug).sort()).toEqual([...expected].sort());
	expect(catalog.models.every((m: { default_reasoning_level: string }) => m.default_reasoning_level === "high")).toBe(true);
	expect(catalog.models.every((m: { supported_reasoning_levels: { effort: string }[] }) =>
		m.supported_reasoning_levels.some((l) => l.effort === "high"))).toBe(true);
});

test("the occ and ocdx handle sets are identical", () => {
	expect(handles("occ.sh")).toEqual(handles("ocdx.sh"));
});
