import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { writeConfig } from "../lib/install.mjs";

const REPO = join(import.meta.dir, "..");
const vendor = JSON.parse(readFileSync(join(REPO, "vendor.json"), "utf8"));
const ALL_FORKS = Object.keys(vendor.forks).map((name) => `local/${name}`);
const FORKS_MINUS_WORKFLOWS = ALL_FORKS.filter((name) => name !== "local/pi-dynamic-workflows-safe");
const SCOPE = [
	"openrouter/deepseek/deepseek-v4-flash-0731",
	"openrouter/deepseek/deepseek-v4-pro-0813",
	"openrouter/z-ai/glm-5.2",
	"openrouter/z-ai/glm-5.3",
	"openrouter/moonshotai/kimi-k3",
	"openrouter/qwen/qwen3.8-max",
	"openai/gpt-5.6-sol",
	"openai/gpt-5.6-terra",
	"openai/gpt-5.6-luna",
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

function runWriter() {
	writeConfig({
		mainPath,
		pPath,
		wfPath,
		sttPath,
		npmPkgPath,
		pNpmPkgPath,
		wfNpmPkgPath,
		piVersion: "0.84.2",
		keybindingsSrcPath: join(REPO, "config/keybindings.json"),
		mainKeybindsPath: keybinds[0],
		pKeybindsPath: keybinds[1],
		wfKeybindsPath: keybinds[2],
		compactionSrcPath: join(REPO, "config/compaction.json"),
		modelsStorePath,
	});
}

test("the model scope lands on all three profiles", () => {
	runWriter();
	expect(JSON.parse(readFileSync(mainPath, "utf8")).enabledModels).toEqual(SCOPE);
	expect(JSON.parse(readFileSync(wfPath, "utf8")).enabledModels).toEqual(SCOPE);
	expect(JSON.parse(readFileSync(pPath, "utf8")).enabledModels).toEqual(SCOPE);
});

test("pi loads every fork except workflows; piwf loads all forks", () => {
	runWriter();
	const main = JSON.parse(readFileSync(mainPath, "utf8"));
	expect(main.packages).toEqual(["npm:user-pkg", ...FORKS_MINUS_WORKFLOWS]);
	const wf = JSON.parse(readFileSync(wfPath, "utf8"));
	expect(wf.packages).toEqual(ALL_FORKS);
});

test("user-persisted values survive the rewrite", () => {
	runWriter();
	const main = JSON.parse(readFileSync(mainPath, "utf8"));
	expect(main.httpProxy).toBe("http://keep-main");
	expect(main.defaultModel).toBe("gpt-5.6-sol");
	const wf = JSON.parse(readFileSync(wfPath, "utf8"));
	expect(wf.defaultModel).toBe("deepseek/deepseek-v4-pro-0813");
	expect(wf.httpProxy).toBe("http://keep-wf");
	expect(wf.compaction.reserveTokens).toBe(99000);
	expect(wf.quietStartup).toBeUndefined();
	const p = JSON.parse(readFileSync(pPath, "utf8"));
	expect(p.defaultModel).toBe("deepseek/deepseek-v4-flash-0731");
	expect(p.quietStartup).toBe(true);
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
