import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { resolveAgentDir } from "./agent-dir.ts";
import { writeFileAtomic } from "./atomic-write.ts";

// Digests only: the record has to survive a restart so a later session can tell this package's
// own output from content a user authored, without keeping a copy of either document.
const MAX_RECORDED_OUTPUTS = 64;

function provenanceFilePath(): string {
	return join(resolveAgentDir(), "extensions", "pi-continue", "written-outputs.json");
}

function contentDigest(content: string): string {
	return createHash("sha256").update(content, "utf8").digest("hex");
}

function readRecordedDigests(): Record<string, string> {
	const path = provenanceFilePath();
	try {
		if (!existsSync(path)) return {};
		const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
		if (typeof parsed !== "object" || parsed === null) return {};
		const digests: Record<string, string> = {};
		for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
			if (typeof value === "string") digests[key] = value;
		}
		return digests;
	} catch {
		return {};
	}
}

/** Report whether the content now at a path is exactly what this package last wrote there. */
export function wasWrittenByPackage(path: string, content: string): boolean {
	return readRecordedDigests()[path] === contentDigest(content);
}

/** Remember what this package wrote so a later session can replace its own output unprompted. */
export async function recordPackageWrite(path: string, content: string): Promise<void> {
	const target = provenanceFilePath();
	const digests = readRecordedDigests();
	delete digests[path];
	const entries: [string, string][] = [...Object.entries(digests), [path, contentDigest(content)]];
	const kept = entries.slice(Math.max(0, entries.length - MAX_RECORDED_OUTPUTS));
	try {
		await mkdir(dirname(target), { recursive: true });
		await writeFileAtomic(target, `${JSON.stringify(Object.fromEntries(kept), null, 2)}\n`, { noFollow: true });
	} catch {
		// Provenance is an optimization: a record that cannot be saved only means the next
		// replacement of that file asks for confirmation again.
	}
}
