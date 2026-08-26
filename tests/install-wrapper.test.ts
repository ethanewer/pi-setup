import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const installer = readFileSync(join(import.meta.dir, "..", "install.sh"), "utf8");
const doctor = readFileSync(join(import.meta.dir, "..", "bin", "pi-setup-doctor"), "utf8");

test("every Bun entry point uses the operating system CA store", () => {
	expect(installer).toContain('"$BUN_BIN" --use-system-ca add --global');
	expect(installer.match(/exec "\\?\$BUN_BIN" --use-system-ca "\\?\$ROOT\/dist\/bun\/cli\.js"/g)).toHaveLength(3);
	expect(installer).toContain('exec "$BUN_BIN" --use-system-ca "$ROOT/bin/agent-browser.js" "$@"');
	expect(installer).toContain('exec "\\$BUN_BIN" --use-system-ca "$TARGET" "\\$@"');
});

test("installer applies the version-guarded Pi reasoning-details patch", () => {
	expect(installer).toContain('PI_AI_REASONING_PATCH="$SRC_DIR/patches/pi-ai@0.84.3-reasoning-details.patch"');
	expect(installer).toContain('PI_AI_VERSION="0.84.3"');
	expect(installer).toContain('[[ "$PI_AI_INSTALLED_VERSION" == "$PI_AI_VERSION" ]]');
	expect(installer).toContain("patch --dry-run --batch --forward");
	expect(installer).toContain('"$BUN_BIN" "$SRC_DIR/bin/verify-pi-ai-reasoning-fix" "$PI_AI_ROOT"');
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
	expect(doctor).toContain('PINNED_PI_AI="$(sed -n');
	expect(doctor).toContain('"Pi AI|$PINNED_PI_AI|$INSTALLED_PI_AI"');
	expect(doctor).toContain('"$JS" "$PI_AI_VERIFIER" "$PI_AI_ROOT"');
	expect(doctor).not.toContain("appendOpenAIReasoningDetail(preservedDetails, detail)");
});

test("pi and piwf both reject an inherited p profile environment", () => {
	// A tmux server started from `p` retains PI_SKIP_VERSION_CHECK (and friends). Both
	// full wrappers must drop them, or a later session silently runs a different profile.
	expect(installer.match(/unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK/g)).toHaveLength(2);
});
