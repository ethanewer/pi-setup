import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const installer = readFileSync(join(import.meta.dir, "..", "install.sh"), "utf8");

test("every Bun entry point uses the operating system CA store", () => {
	expect(installer).toContain('"$BUN_BIN" --use-system-ca add --global');
	expect(installer.match(/exec "\\?\$BUN_BIN" --use-system-ca "\\?\$ROOT\/dist\/bun\/cli\.js"/g)).toHaveLength(3);
	expect(installer).toContain('exec "$BUN_BIN" --use-system-ca "$ROOT/bin/agent-browser.js" "$@"');
	expect(installer).toContain('exec "\\$BUN_BIN" --use-system-ca "$TARGET" "\\$@"');
});

test("pi and piwf both reject an inherited p profile environment", () => {
	// A tmux server started from `p` retains PI_SKIP_VERSION_CHECK (and friends). Both
	// full wrappers must drop them, or a later session silently runs a different profile.
	expect(installer.match(/unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK/g)).toHaveLength(2);
});
