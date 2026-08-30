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

test("installer patches the Pi npm bundle entrypoint after the library patch", () => {
	expect(installer).toContain('join(SRC_DIR, "bin", "patch-pi-bundle")');
	expect(installer).toContain("refusing to leave the npm entrypoint unpatched");
	// The library patch must land first so a bundle failure leaves nothing half-patched.
	expect(installer.indexOf("applyPiAiReasoningPatch(bunBin")).toBeLessThan(
		installer.indexOf('join(SRC_DIR, "bin", "patch-pi-bundle")'),
	);
	expect(doctor).toContain("openai-completions-*.js");
	expect(doctor).toContain("normalizeOpenAIReasoningDetails");
});

test("patch-pi-bundle rewrites the pinned bundle chunk, idempotently", () => {
	const versions = JSON.parse(readFileSync(join(root, "lib", "versions.json"), "utf8"));
	const fake = mkdtempSync(join(tmpdir(), "pi-bundle-"));
	const chunks = join(fake, "dist", "bundle", "chunks");
	mkdirSync(chunks, { recursive: true });
	writeFileSync(join(fake, "package.json"), JSON.stringify({ version: versions.pi }));
	const parseOld =
		"function parseOpenAIReasoningDetails(signature){if(signature)try{" +
		"let parsed=JSON.parse(signature);return Array.isArray(parsed)&&" +
		"parsed.length>0&&parsed.every(isOpenAIReasoningDetail)?parsed:void 0}" +
		"catch{return}}";
	writeFileSync(
		join(chunks, "openai-completions-TEST.js"),
		`function appendOpenAIReasoningDetail(details,detail){details.push({...detail})}${parseOld}`,
	);
	const script = join(root, "bin", "patch-pi-bundle");
	try {
		const first = Bun.spawnSync(["bun", script, fake]);
		expect(first.exitCode).toBe(0);
		const patched = readFileSync(join(chunks, "openai-completions-TEST.js"), "utf8");
		expect(patched).toContain("normalizeOpenAIReasoningDetails(parsed)");
		expect(patched.match(/function appendOpenAIReasoningDetail/g)).toHaveLength(1);
		const second = Bun.spawnSync(["bun", script, fake]);
		expect(second.exitCode).toBe(0);
		expect(second.stdout.toString()).toContain("already patched");
		writeFileSync(join(fake, "package.json"), JSON.stringify({ version: "0.0.0" }));
		const wrongVersion = Bun.spawnSync(["bun", script, fake]);
		expect(wrongVersion.exitCode).toBe(1);
		expect(wrongVersion.stderr.toString()).toContain("version-guarded");
	} finally {
		rmSync(fake, { recursive: true, force: true });
	}
});

test("doctor uses the independent Pi AI pin and behavior verifier", () => {
	expect(doctor).toContain('PINNED_PI_AI="$("$JS"');
	expect(doctor).toContain('"Pi AI|$PINNED_PI_AI|$INSTALLED_PI_AI"');
	expect(doctor).toContain('"$JS" "$PI_AI_VERIFIER" "$PI_AI_ROOT"');
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
