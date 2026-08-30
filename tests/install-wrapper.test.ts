import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const wrappers = join(root, "lib/wrappers");
const installer = readFileSync(join(root, "lib", "install.mjs"), "utf8");
const doctor = readFileSync(join(root, "bin", "pi-setup-doctor"), "utf8");

test("every Bun entry point uses the operating system CA store", () => {
	expect(readFileSync(join(root, "lib/install.mjs"), "utf8")).toContain('"--use-system-ca"');
	for (const name of ["pi.sh", "p.sh", "piwf.sh", "agent-browser.sh", "pi-agent-browser-cli.sh"]) {
		expect(readFileSync(join(wrappers, name), "utf8")).toContain("--use-system-ca");
	}
	for (const name of ["pi.cmd", "p.cmd", "piwf.cmd", "agent-browser.cmd", "pi-agent-browser-cli.cmd"]) {
		expect(readFileSync(join(wrappers, name), "utf8")).toContain("--use-system-ca");
	}
});

test("installer applies the version-guarded Pi reasoning-details patch", () => {
	const versions = JSON.parse(readFileSync(join(root, "lib", "versions.json"), "utf8"));
	expect(versions.piAi).toBe("0.84.4");
	expect(installer).toContain("pi-ai@${versions.piAi}-reasoning-details.patch");
	expect(installer).toContain("refusing to apply a version-specific patch");
	expect(installer).toContain("patch --dry-run --batch --forward");
	expect(installer).toContain("verify-pi-ai-reasoning-fix");
});

test("reasoning-fix verifier executes its stream and replay behavior checks", () => {
	const root = mkdtempSync(join(tmpdir(), "pi-ai-verifier-"));
	const api = join(root, "dist", "api");
	mkdirSync(api, { recursive: true });
	writeFileSync(join(root, "package.json"), '{"type":"module"}');
	writeFileSync(
		join(api, "openai-completions.js"),
		String.raw`
export async function* streamSimple(model, context) {
	const signature = context.messages[0].content.find((block) => block.type === "thinking").thinkingSignature;
	const details = JSON.parse(signature);
	const replayed = [
		{ ...details[0], text: details[0].text + details[1].text, signature: details[1].signature, format: details[1].format },
		details[2],
		{ ...details[3], summary: details[3].summary + details[4].summary, index: details[4].index },
	];
	await fetch(model.baseUrl + "/chat/completions", {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify({ messages: [{ role: "assistant", reasoning_details: replayed }] }),
	});
	yield {
		type: "done",
		message: {
			content: [{
				type: "thinking",
				thinkingSignature: JSON.stringify([
					{ type: "reasoning.text", text: "New stream", signature: "new-signature" },
				]),
			}],
		},
	};
}
`,
	);
	try {
		const result = Bun.spawnSync(
			["bun", join(import.meta.dir, "..", "bin", "verify-pi-ai-reasoning-fix"), root],
			{ cwd: join(import.meta.dir, "..") },
		);
		expect(result.exitCode).toBe(0);
		expect(result.stdout.toString()).toContain("reasoning-details fix verified");
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test("doctor uses the independent Pi AI pin and behavior verifier", () => {
	expect(doctor).toContain('PINNED_PI_AI="$("$JS"');
	expect(doctor).toContain('"Pi AI|$PINNED_PI_AI|$INSTALLED_PI_AI"');
	// The verifier is ESM with a bun shebang; node cannot load it as .js, so the doctor
	// must resolve a bun binary explicitly even when its $JS fallback chain found node.
	expect(doctor).toContain('"$BUN_BIN" "$PI_AI_VERIFIER" "$PI_AI_ROOT"');
	expect(doctor).toContain('BUN_BIN="$(command -v bun)"');
	expect(doctor).not.toContain("appendOpenAIReasoningDetail(preservedDetails, detail)");
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
