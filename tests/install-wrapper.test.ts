import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const wrappers = join(root, "lib/wrappers");

test("every Bun entry point uses the operating system CA store", () => {
	expect(readFileSync(join(root, "lib/install.mjs"), "utf8")).toContain('"--use-system-ca"');
	for (const name of ["pi.sh", "p.sh", "piwf.sh", "agent-browser.sh", "pi-agent-browser-cli.sh"]) {
		expect(readFileSync(join(wrappers, name), "utf8")).toContain("--use-system-ca");
	}
	for (const name of ["pi.cmd", "p.cmd", "piwf.cmd", "agent-browser.cmd", "pi-agent-browser-cli.cmd"]) {
		expect(readFileSync(join(wrappers, name), "utf8")).toContain("--use-system-ca");
	}
});

test("pi and piwf both reject an inherited p profile environment", () => {
	const pi = readFileSync(join(wrappers, "pi.sh"), "utf8");
	const piwf = readFileSync(join(wrappers, "piwf.sh"), "utf8");
	expect(pi).toContain("unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK");
	expect(piwf).toContain("unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK");
	expect(pi).toContain('"$HOME/.pi/agent-wf"');
	expect(readFileSync(join(wrappers, "pi.cmd"), "utf8")).toContain("%USERPROFILE%\\.pi\\agent-wf");
	expect(readFileSync(join(wrappers, "piwf.cmd"), "utf8")).toContain("%USERPROFILE%\\.pi\\agent-wf");
});
