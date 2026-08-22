import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

// install.sh embeds its settings writer in a heredoc. Extract that exact script and run
// it against fixture files, so the committed tests cover what install.sh actually writes
// (the fork split, the model scope, and the preserve-user-keys rule) instead of a copy.
const installer = readFileSync(join(import.meta.dir, "..", "install.sh"), "utf8");
const START = 'cat > "$CONFIG_SCRIPT" <<\'JS\'\n';
const start = installer.indexOf(START);
const end = installer.indexOf("\nJS\n", start);
expect(start).toBeGreaterThan(-1);
const configScript = installer.slice(start + START.length, end);

const REPO = join(import.meta.dir, "..");
const SCOPE = [
	"openrouter/z-ai/glm-5.3",
	"openai/gpt-5.6-luna",
	"openai/gpt-5.6-sol",
	"openai/gpt-5.6-terra",
	"openrouter/deepseek/deepseek-v4-flash-0731",
	"openrouter/deepseek/deepseek-v4-pro-0813",
];
const FORKS_MINUS_WORKFLOWS = [
	"local/pi-voice-stt-safe",
	"local/pi-agent-browser-native-safe",
	"local/pi-context-handoff",
	"local/pi-codex-compaction",
	"local/pi-btw-side",
	"local/pi-process-monitor-safe",
	"local/pi-setup-maintenance",
	"local/pi-model-prices",
];
const ALL_FORKS = [
	"local/pi-voice-stt-safe",
	"local/pi-agent-browser-native-safe",
	"local/pi-dynamic-workflows-safe",
	"local/pi-context-handoff",
	"local/pi-codex-compaction",
	"local/pi-btw-side",
	"local/pi-process-monitor-safe",
	"local/pi-setup-maintenance",
	"local/pi-model-prices",
];

const dir = mkdtempSync(join(tmpdir(), "pi-config-writer-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const mainPath = join(dir, "agent", "settings.json");
const pPath = join(dir, "agent-p", "settings.json");
const wfPath = join(dir, "agent-wf", "settings.json");
const sttPath = join(dir, "agent", "stt.json");
const npmPkgPath = join(dir, "agent", "npm", "package.json");
const pNpmPkgPath = join(dir, "agent-p", "npm", "package.json");
const wfNpmPkgPath = join(dir, "agent-wf", "npm", "package.json");
const keybinds = ["agent", "agent-p", "agent-wf"].map((d) => join(dir, d, "keybindings.json"));
const modelsStorePath = join(dir, "agent", "models-store.json");

for (const d of ["agent", "agent/npm", "agent-p/npm", "agent-wf/npm"]) {
	mkdirSync(join(dir, d), { recursive: true });
}
writeFileSync(mainPath, JSON.stringify({
	defaultProvider: "openai",
	defaultModel: "gpt-5.6-sol",
	httpProxy: "http://keep-main",
	packages: ["npm:pi-btw", "npm:user-pkg"],
}));
// piwf and p carry values a previous run persisted: they must survive the rewrite.
writeFileSync(wfPath, JSON.stringify({
	defaultProvider: "openrouter",
	defaultModel: "deepseek/deepseek-v4-pro-0813",
	httpProxy: "http://keep-wf",
	packages: ["npm:pi-continue"],
	compaction: { reserveTokens: 99000 },
}));
writeFileSync(pPath, JSON.stringify({
	defaultProvider: "openrouter",
	defaultModel: "deepseek/deepseek-v4-flash-0731",
}));
writeFileSync(npmPkgPath, JSON.stringify({ dependencies: { "pi-btw": "1.0.0", "left-alone": "2.0.0" } }));
writeFileSync(pNpmPkgPath, JSON.stringify({ dependencies: { "pi-continue": "1.0.0" } }));
writeFileSync(wfNpmPkgPath, JSON.stringify({ dependencies: { "left-alone-wf": "3.0.0" } }));
writeFileSync(modelsStorePath, JSON.stringify({
	openai: { models: [{ id: "gpt-5.6-sol", contextWindow: 272000 }] },
	openrouter: {
		models: [
			{ id: "z-ai/glm-5.3", contextWindow: 1048576 },
			{ id: "deepseek/deepseek-v4-flash-0731", contextWindow: 1048576 },
			{ id: "deepseek/deepseek-v4-pro-0813", contextWindow: 1048575 },
		],
	},
}));

const scriptPath = join(dir, "config-writer.mjs");
writeFileSync(scriptPath, configScript);

function runWriter() {
	const result = Bun.spawnSync([
		"bun",
		scriptPath,
		mainPath,
		pPath,
		wfPath,
		sttPath,
		npmPkgPath,
		pNpmPkgPath,
		wfNpmPkgPath,
		"0.84.2",
		join(REPO, "config/keybindings.json"),
		keybinds[0],
		keybinds[1],
		keybinds[2],
		join(REPO, "config/compaction.json"),
		modelsStorePath,
	]);
	expect(result.exitCode).toBe(0);
}

test("the model scope lands on all three profiles", () => {
	runWriter();
	expect(JSON.parse(readFileSync(mainPath, "utf8")).enabledModels).toEqual(SCOPE);
	expect(JSON.parse(readFileSync(wfPath, "utf8")).enabledModels).toEqual(SCOPE);
	expect(JSON.parse(readFileSync(pPath, "utf8")).enabledModels).toEqual(SCOPE);
});

test("pi loads every fork except workflows; piwf loads all nine", () => {
	runWriter();
	const main = JSON.parse(readFileSync(mainPath, "utf8"));
	expect(main.packages).toEqual(["npm:user-pkg", ...FORKS_MINUS_WORKFLOWS]);
	const wf = JSON.parse(readFileSync(wfPath, "utf8"));
	expect(wf.packages).toEqual(ALL_FORKS);
});

test("user-persisted values survive the rewrite", () => {
	runWriter();
	// main keeps its seeded defaults and unrelated keys; the managed npm package is dropped.
	const main = JSON.parse(readFileSync(mainPath, "utf8"));
	expect(main.httpProxy).toBe("http://keep-main");
	expect(main.defaultModel).toBe("gpt-5.6-sol");
	// piwf keeps its own default model, unrelated keys, and its raised reserve.
	const wf = JSON.parse(readFileSync(wfPath, "utf8"));
	expect(wf.defaultModel).toBe("deepseek/deepseek-v4-pro-0813");
	expect(wf.httpProxy).toBe("http://keep-wf");
	expect(wf.compaction.reserveTokens).toBe(99000);
	expect(wf.quietStartup).toBeUndefined();
	// p keeps its own default model and stays quiet.
	const p = JSON.parse(readFileSync(pPath, "utf8"));
	expect(p.defaultModel).toBe("deepseek/deepseek-v4-flash-0731");
	expect(p.quietStartup).toBe(true);
	// Compaction is raised to the policy floor where it was below it.
	expect(main.compaction.reserveTokens).toBe(68000);
	expect(p.compaction.reserveTokens).toBe(68000);
});

test("the writer is idempotent", () => {
	runWriter();
	const before = [mainPath, pPath, wfPath].map((p) => readFileSync(p, "utf8"));
	runWriter();
	const after = [mainPath, pPath, wfPath].map((p) => readFileSync(p, "utf8"));
	expect(after).toEqual(before);
});

test("npm-installed fork copies are pruned from all three manifests", () => {
	runWriter();
	const main = JSON.parse(readFileSync(npmPkgPath, "utf8"));
	expect(main.dependencies).toEqual({ "left-alone": "2.0.0" });
	expect(main.private).toBe(true);
	const lean = JSON.parse(readFileSync(pNpmPkgPath, "utf8"));
	expect(lean.dependencies).toEqual({});
	const wf = JSON.parse(readFileSync(wfNpmPkgPath, "utf8"));
	expect(wf.dependencies).toEqual({ "left-alone-wf": "3.0.0" });
});
