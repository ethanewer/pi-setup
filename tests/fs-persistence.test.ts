import { expect, test } from "bun:test";
import {
	PRIVATE_FILE_MODE,
	resolvePersistenceFs,
	writeJsonAtomicWithBackupStrict,
} from "../forks/pi-dynamic-workflows-safe/src/fs-persistence";

test("strict workflow backups are created owner-only", () => {
	const writes: Array<{ path: string; options: unknown }> = [];
	const fs = resolvePersistenceFs({
		writeFileSync: ((path: string, _data: unknown, options: unknown) => {
			writes.push({ path, options });
		}) as never,
		renameSync: (() => {}) as never,
	});

	writeJsonAtomicWithBackupStrict(fs, "/private/workflow.json", { prompt: "secret" });

	expect(writes).toEqual([
		{ path: "/private/workflow.json.tmp", options: { mode: PRIVATE_FILE_MODE } },
		{ path: "/private/workflow.json.bak", options: { mode: PRIVATE_FILE_MODE } },
	]);
});
