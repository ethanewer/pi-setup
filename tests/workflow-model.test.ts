import { afterEach, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { WORKFLOW_AUTHORING_FROZEN_FILES } from "../forks/pi-dynamic-workflows-safe/src/workflow-authoring-coverage";
import { createRunPersistence, isAutoResumeEligibleRun } from "../forks/pi-dynamic-workflows-safe/src/run-persistence";
import { workflowInstallId } from "../forks/pi-dynamic-workflows-safe/src/workflow-paths";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadSubagentModelConfig, saveSubagentModelConfig } from "../forks/pi-dynamic-workflows-safe/src/subagent-model-config";
import { pinnedWorkflowModels, registerWorkflowModelCommand } from "../forks/pi-dynamic-workflows-safe/src/workflow-model-command";
import { createAssistantMessageEventStream, type Model } from "../forks/pi-dynamic-workflows-safe/node_modules/@earendil-works/pi-ai";
import { DefaultResourceLoader, ModelRegistry, ModelRuntime, SettingsManager } from "../forks/pi-dynamic-workflows-safe/node_modules/@earendil-works/pi-coding-agent";
import { resolveSubagentSnapshot } from "../forks/pi-dynamic-workflows-safe/src/subagent-model-snapshot";
import { resolveRunModelStrict } from "../forks/pi-dynamic-workflows-safe/src/model-spec";
import { runWorkflow } from "../forks/pi-dynamic-workflows-safe/src/workflow";
import { WorkflowAgent } from "../forks/pi-dynamic-workflows-safe/src/agent";
import { WorkflowManager } from "../forks/pi-dynamic-workflows-safe/src/workflow-manager";

const dirs: string[] = [];
function temp() {
  const dir = mkdtempSync(join(tmpdir(), "workflow-model-"));
  dirs.push(dir);
  return dir;
}
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });

test("config saves one trimmed model and migrates only the old medium tier", () => {
  const dir = temp();
  const path = join(dir, "subagent-model.json");
  const legacy = join(dir, "model-tiers.json");
  expect(loadSubagentModelConfig(path)).toBeNull();
  writeFileSync(legacy, JSON.stringify({ tiers: { small: "p/s", medium: "p/m:high", big: "p/b" } }));
  expect(loadSubagentModelConfig(path, legacy, strictRegistry(["m"]))).toEqual({ model: "p/m", thinking: "high" });
  saveSubagentModelConfig({ model: " p/new " }, path);
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "p/new" });
  expect(loadSubagentModelConfig(path)).toEqual({ model: "p/new" });
  expect(JSON.parse(readFileSync(legacy, "utf8")).tiers.big).toBe("p/b");
});

test("migration normalizes legacy specs after registry resolution", () => {
  const path = join(temp(), "subagent-model.json");
  const legacy = join(path, "..", "model-tiers.json");
  writeFileSync(legacy, JSON.stringify({ tiers: { medium: "p/m:high" } }));
  expect(loadSubagentModelConfig(path, legacy, strictRegistry(["m"]))).toEqual({ model: "p/m", thinking: "high" });
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "p/m", thinking: "high" });
});

test("bare legacy ids need the registry, and ambiguous ones fail without writing", () => {
  const path = join(temp(), "subagent-model.json");
  const legacy = join(path, "..", "model-tiers.json");
  writeFileSync(legacy, JSON.stringify({ tiers: { medium: "m:high" } }));
  expect(() => loadSubagentModelConfig(path, legacy)).toThrow("requires a model registry");
  expect(() => readFileSync(path)).toThrow();
  const registry = { getAll: () => [model("m:high"), { ...model("m:high"), provider: "q" }] };
  expect(() => loadSubagentModelConfig(path, legacy, registry)).toThrow("ambiguous");
  expect(() => readFileSync(path)).toThrow();
});

test("invalid config never silently falls back to another model", () => {
  const path = join(temp(), "subagent-model.json");
  expect(() => saveSubagentModelConfig({ model: " " }, path)).toThrow();
  for (const value of ["{", "null", '{"model":""}', '{"tiers":{"medium":"p/m"}}', '{"model":"p/m","thinking":"bogus"}', '{"model":"p/m","thinking":42}']) {
    writeFileSync(path, value);
    expect(() => loadSubagentModelConfig(path)).toThrow();
  }
});

test("picker preserves scoped order, deduplicates pins and keeps pin thinking", () => {
  const ctx = { scopedModels: [
    { model: { provider: "p", id: "b" }, thinkingLevel: "high" },
    { model: { provider: "p", id: "a" } },
    { model: { provider: "p", id: "b" }, thinkingLevel: "high" },
  ] };
  expect(pinnedWorkflowModels(ctx as never)).toEqual([
    { model: "p/b", thinkingLevel: "high", label: "1. p/b [thinking: high]" },
    { model: "p/a", thinkingLevel: undefined, label: "2. p/a" },
  ]);
  expect(pinnedWorkflowModels({ scopedModels: [] })).toEqual([]);
  // Same model pinned with different thinking deduplicates to one identity;
  // no single pin owns the thinking level.
  const mixed = { scopedModels: [
    { model: { provider: "p", id: "b" }, thinkingLevel: "high" },
    { model: { provider: "p", id: "b" }, thinkingLevel: "low" },
  ] };
  expect(pinnedWorkflowModels(mixed as never)).toEqual([
    { model: "p/b", thinkingLevel: undefined, label: "1. p/b" },
  ]);
});

test("empty pins do not enumerate the catalogue or show a selection dialog", async () => {
  const commands = new Map<string, any>();
  registerWorkflowModelCommand({ registerCommand: (name: string, cmd: unknown) => commands.set(name, cmd) } as never);
  expect(commands.has("workflow-model")).toBe(true);
  expect(commands.get("workflow-model").handler).toBe(commands.get("workflows-models").handler);
  const notices: string[] = [];
  await commands.get("workflow-model").handler("", {
    hasUI: true, waitForIdle: async () => {}, scopedModels: [],
    modelRegistry: { getAvailable() { throw new Error("must not enumerate"); } },
    ui: { notify: (message: string) => notices.push(message), select() { throw new Error("must not select"); } },
  });
  expect(notices[0]).toContain("No pinned models");
});

test("script, phase, role and tier selectors cannot override the single run model", async () => {
  const calls: any[] = [];
  const models: string[] = [];
  const result = await runWorkflow(`
    export const meta = { name: 'single', description: 'test', model: 'bad/meta', phases: [{ title: 'Review', model: 'bad/phase' }] };
    phase('Review');
    return await parallel([
      () => agent('one', { model: 'bad/explicit', tier: 'big', agentType: 'reviewer' }),
      () => agent('two', { tier: 'small' }),
      () => agent('three')
    ]);
  `, {
    cwd: temp(), persistLogs: false, subagentModel: "p/chosen:high", mainModel: "p/main",
    agentRegistry: new Map([["reviewer", { name: "reviewer", model: "bad/role", prompt: "Review carefully", source: "user" }]]) as never,
    agent: { async run(_prompt, options) { calls.push(options); return "ok"; } },
    onAgentStart: (event) => { if (event.model) models.push(event.model); },
  });
  expect(result.result).toEqual(["ok", "ok", "ok"]);
  expect(models).toEqual(["p/chosen:high", "p/chosen:high", "p/chosen:high"]);
  expect(calls.every((call) => !("model" in call) && !("tier" in call))).toBe(true);
  expect(calls[0].instructions).toContain("Review carefully");
});

test("picker saves only a selected pin and can replace invalid config", async () => {
  const commands = new Map<string, any>();
  const saved: unknown[] = [];
  registerWorkflowModelCommand({ registerCommand: (name: string, cmd: unknown) => commands.set(name, cmd) } as never, {
    load() { throw new Error("invalid JSON"); },
    save(value) { saved.push(value); },
  });
  const choices = ["1. p/pinned [thinking: high]", "Use pinned/default thinking"];
  const ctx = {
    hasUI: true, waitForIdle: async () => {},
    scopedModels: [{ model: { provider: "p", id: "pinned" }, thinkingLevel: "high" }],
    modelRegistry: { getAvailable() { throw new Error("must not enumerate"); } },
    ui: { notify() {}, async select(_title: string, items: string[]) {
      const choice = choices.shift();
      expect(items).toContain(choice);
      return choice;
    } },
  };
  await commands.get("workflow-model").handler("", ctx);
  expect(saved).toEqual([{ model: "p/pinned", thinking: "high" }]);
  ctx.ui.select = async () => undefined;
  await commands.get("workflow-model").handler("", ctx);
  expect(saved).toHaveLength(1);
});

test("nested workflows and threaded turns retain the run model", async () => {
  const models: string[] = [];
  const threads: unknown[] = [];
  const result = await runWorkflow(`
    export const meta = { name: 'parent', description: 'test' };
    await agent('first', { thread: 'worker', model: 'bad/first' });
    await workflow('child');
    return await agent('last', { thread: 'worker', tier: 'big' });
  `, {
    cwd: temp(), persistLogs: false, subagentModel: "p/chosen", mainModel: "p/main",
    loadSavedWorkflow: () => `export const meta = { name: 'child', description: 'test', model: 'bad/child' }; return await agent('middle', { thread: 'worker', model: 'bad/middle' });`,
    agent: { async run(_prompt, options) { threads.push(options.thread); return "ok"; } },
    onAgentStart: (event) => { if (event.model) models.push(event.model); },
  });
  expect(result.result).toBe("ok");
  expect(models).toEqual(["p/chosen", "p/chosen", "p/chosen"]);
  expect(threads).toEqual(["worker", "worker", "worker"]);
});

test("unavailable chosen model fails before a session can use a fallback", async () => {
  const runner = new WorkflowAgent({
    cwd: temp(), tools: [], subagentModel: "missing/model", mainModel: "p/main",
    modelRegistry: { getAvailable: () => [], getAll: () => [], find: () => undefined } as never,
  });
  await expect(runner.run("test", { model: "p/override", tier: "big" } as never)).rejects.toThrow("Subagent model");
});

function model(id: string): Model<any> {
  return { id, name: id, provider: "p", api: "openai-completions", baseUrl: "http://x", contextWindow: 1, maxTokens: 1 } as unknown as Model<any>;
}
const strictRegistry = (ids: string[]) => ({ getAll: () => ids.map(model) });

async function realSessionFixture() {
  const cwd = temp();
  const agentDir = temp();
  const settingsManager = SettingsManager.inMemory({ defaultThinkingLevel: "low", compaction: { enabled: false }, retry: { enabled: false } });
  const runtime = await ModelRuntime.create({ authPath: join(agentDir, "auth.json"), modelsPath: null, refreshOnCreate: false });
  const seen: Array<{ id: string; thinking: unknown }> = [];
  runtime.registerProvider("snapshot-test", {
    api: "openai-completions", baseUrl: "http://unused.invalid", apiKey: "test-only",
    models: [{ id: "m", name: "m", reasoning: true, input: ["text"], contextWindow: 100000, maxTokens: 1000,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
    streamSimple(model, _context, options) {
      seen.push({ id: model.id, thinking: options?.reasoning });
      const stream = createAssistantMessageEventStream();
      const message = { role: "assistant" as const, content: [{ type: "text" as const, text: "ok" }],
        api: model.api, provider: model.provider, model: model.id, stopReason: "stop" as const, timestamp: Date.now(),
        usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } };
      stream.push({ type: "done", reason: "stop", message });
      stream.end(message);
      return stream;
    },
  });
  const modelRegistry = new ModelRegistry(runtime);
  const resourceLoader = new DefaultResourceLoader({ cwd, agentDir, settingsManager,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true });
  await resourceLoader.reload();
  return { cwd, seen, settingsManager, modelRegistry, session: { agentDir, settingsManager, resourceLoader, modelRuntime: runtime } };
}

test("real sessions keep default thinking through one-shot and threaded turns", async () => {
  const fixture = await realSessionFixture();
  const runner = new WorkflowAgent({ ...fixture, subagentModel: "snapshot-test/m" });
  await runner.run("first");
  fixture.settingsManager.setDefaultThinkingLevel("high");
  fixture.settingsManager.setModelThinkingLevel("snapshot-test", "m", "high");
  await runner.run("second", { thread: "worker" });
  await runner.run("third", { thread: "worker" });
  await runner.run("fourth");
  expect(fixture.seen).toEqual(Array(4).fill({ id: "m", thinking: "low" }));
});

test("direct and nested runtime calls pass saved thinking to real sessions", async () => {
  const fixture = await realSessionFixture();
  const path = join(temp(), "subagent-model.json");
  saveSubagentModelConfig({ model: "snapshot-test/m", thinking: "high" }, path);
  await runWorkflow(`export const meta = {name: 'direct', description: 'test'}; await agent('first'); return await workflow('child');`, {
    ...fixture, subagentModelConfigPath: path, persistLogs: false,
    loadSavedWorkflow: () => `export const meta = {name: 'child', description: 'test'}; return await agent('second');`,
  });
  expect(fixture.seen).toEqual(Array(2).fill({ id: "m", thinking: "high" }));
});

test("missing literal suffix model fails in real runner instead of selecting its base", async () => {
  const fixture = await realSessionFixture();
  const runner = new WorkflowAgent({ ...fixture, subagentModel: "snapshot-test/m:high" });
  await expect(runner.run("must not call base")).rejects.toMatchObject({ code: "MODEL_NOT_FOUND", recoverable: false });
  expect(fixture.seen).toEqual([]);
});

test("snapshot preserves empty explicit selection and resolves defaults only once", () => {
  const path = join(temp(), "subagent-model.json");
  const settingsManager = SettingsManager.inMemory({ defaultThinkingLevel: "low" });
  const snapshot = resolveSubagentSnapshot({ subagentModel: "", subagentModelConfigPath: path, session: { settingsManager } });
  expect(snapshot).toEqual({ subagentModel: "", subagentThinking: "low" });
  saveSubagentModelConfig({ model: "p/new", thinking: "high" }, path);
  settingsManager.setDefaultThinkingLevel("high");
  expect(resolveSubagentSnapshot({ ...snapshot, subagentModelConfigPath: path, session: { settingsManager } })).toEqual(snapshot);
});

test("migration preserves literal suffixes and slash-containing aggregator ids", () => {
  for (const [legacySpec, entries, expected] of [
    ["p/m:high", [model("m"), model("m:high")], { model: "p/m:high" }],
    ["vendor/m", [{ ...model("vendor/m"), provider: "openrouter" }], { model: "openrouter/vendor/m" }],
  ] as const) {
    const path = join(temp(), "subagent-model.json");
    const legacy = join(path, "..", "model-tiers.json");
    writeFileSync(legacy, JSON.stringify({ tiers: { medium: legacySpec } }));
    expect(loadSubagentModelConfig(path, legacy, { getAll: () => [...entries] })).toEqual(expected);
    expect(JSON.parse(readFileSync(path, "utf8"))).toEqual(expected);
  }
});

test("public runner and runtime migrate with an asynchronously obtained registry", async () => {
  for (const direct of [true, false]) {
    const fixture = await realSessionFixture();
    const path = join(temp(), "subagent-model.json");
    writeFileSync(join(path, "..", "model-tiers.json"), JSON.stringify({ tiers: { medium: "snapshot-test/m:high" } }));
    const { modelRegistry: _registry, ...withoutRegistry } = fixture;
    const options = { ...withoutRegistry, subagentModelConfigPath: path, persistLogs: false };
    if (direct) await new WorkflowAgent(options).run("migration");
    else await runWorkflow(`export const meta = {name:'migration', description:'test'}; return await agent('migration');`, options);
    expect(fixture.seen).toEqual([{ id: "m", thinking: "high" }]);
    expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "snapshot-test/m", thinking: "high" });
  }
});

test("no-config public runners pick one available model and preserve host thinking", async () => {
  for (const direct of [true, false]) {
    const fixture = await realSessionFixture();
    const { modelRegistry: _registry, ...withoutRegistry } = fixture;
    const options = { ...withoutRegistry, subagentModelConfigPath: join(temp(), "subagent-model.json"),
      session: { ...fixture.session, thinkingLevel: "high" as const }, persistLogs: false };
    if (direct) {
      const runner = new WorkflowAgent(options);
      await runner.run("one");
      fixture.settingsManager.setDefaultThinkingLevel("off");
      await runner.run("two", { thread: "worker" });
    } else {
      await runWorkflow(`export const meta = {name:'default', description:'test'}; await agent('one'); return await agent('two');`, options);
    }
    expect(fixture.seen).toEqual(Array(2).fill({ id: "m", thinking: "high" }));
  }
});

test("host session model falls back before settings defaults", () => {
  const settingsManager = SettingsManager.inMemory({ defaultProvider: "settings-p", defaultModel: "settings-m", defaultThinkingLevel: "low" });
  const path = join(temp(), "subagent-model.json");
  const resolved = resolveSubagentSnapshot({ subagentModelConfigPath: path, session: { settingsManager, model: { provider: "host-p", id: "host-m" } } });
  expect(resolved.subagentModel).toBe("host-p/host-m");
  expect(resolved.subagentThinking).toBe("low");
});

test("strict resolution refuses near-miss ids, fabricated ids, and unknown providers", () => {
  const registry = strictRegistry(["chosen-v2", "chosen-v2:free", "other"]);
  expect(resolveRunModelStrict("p/chosen", registry).error).toBeDefined();
  expect(resolveRunModelStrict("p/otherr", registry).error).toBeDefined();
  expect(resolveRunModelStrict("p/other:bogus", registry).error).toBeDefined();
  expect(resolveRunModelStrict("p/other", registry).model?.id).toBe("other");
  expect(resolveRunModelStrict("p/chosen-v2:high", registry).error).toBeDefined();
  expect(resolveRunModelStrict("p/chosen-v2:free:low", registry).error).toBeDefined();
  // A stored id that collides with a thinking-looking suffix stays literal.
  const colliding = strictRegistry(["claude-sonnet-4-5", "claude-sonnet-4-5:high"]);
  expect(resolveRunModelStrict("p/claude-sonnet-4-5:high", colliding).model?.id).toBe("claude-sonnet-4-5:high");
  expect(resolveRunModelStrict("p/claude-sonnet-4-5:thinking", colliding).error).toBeDefined();
  // Removing the literal model must not substitute its base model.
  const plain = strictRegistry(["claude-sonnet-4-5"]);
  expect(resolveRunModelStrict("p/claude-sonnet-4-5:high", plain).error).toBeDefined();
  // Canonical specs never fall back to a bare id under another provider.
  expect(resolveRunModelStrict("deepseek/deepseek-v4-pro", strictRegistry(["deepseek-v4-pro"])).error).toBeDefined();
});

test("short-form aggregator ids canonicalize to the unique authenticated provider", () => {
  const openrouter = { ...model("vendor/m"), provider: "openrouter" };
  const vercel = { ...model("vendor/m"), provider: "vercel-ai-gateway" };
  const catalog = { getAll: () => [openrouter, vercel], getAvailable: () => [openrouter] };
  expect(resolveRunModelStrict("vendor/m", catalog).resolvedSpec).toBe("openrouter/vendor/m");
  expect(resolveRunModelStrict("openrouter/vendor/m", catalog).resolvedSpec).toBe("openrouter/vendor/m");
  expect(resolveRunModelStrict("vendor/m", { getAll: () => [openrouter, vercel], getAvailable: () => [openrouter, vercel] }).error).toBeDefined();
  expect(resolveRunModelStrict("vendor/m", { getAll: () => [openrouter, vercel], getAvailable: () => [] }).error).toBeDefined();
  expect(resolveRunModelStrict("openrouter/vendor/m", { getAll: () => [openrouter], getAvailable: () => [] }).error).toBeDefined();
});

test("saved colon-id configs stay literal and do not take the base model", () => {
  const path = join(temp(), "subagent-model.json");
  writeFileSync(path, JSON.stringify({ model: "p/m:high", thinking: "low" }));
  expect(() => loadSubagentModelConfig(path, undefined, strictRegistry(["m"]))).toThrow("unavailable");
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "p/m:high", thinking: "low" });
  writeFileSync(path, JSON.stringify({ model: "p/m:high" }));
  expect(loadSubagentModelConfig(path, undefined, strictRegistry(["m", "m:high"]))).toEqual({ model: "p/m:high" });
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "p/m:high" });
});

test("saved short-form configs rewrite on load and fail when still ambiguous", () => {
  const openrouter = { ...model("vendor/m"), provider: "openrouter" };
  const vercel = { ...model("vendor/m"), provider: "vercel-ai-gateway" };
  const path = join(temp(), "subagent-model.json");
  writeFileSync(path, JSON.stringify({ model: "vendor/m" }));
  expect(loadSubagentModelConfig(path, undefined, { getAll: () => [openrouter, vercel], getAvailable: () => [openrouter] })).toEqual({
    model: "openrouter/vendor/m",
  });
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "openrouter/vendor/m" });
  writeFileSync(path, JSON.stringify({ model: "vendor/m" }));
  expect(() => loadSubagentModelConfig(path, undefined, { getAll: () => [openrouter, vercel], getAvailable: () => [openrouter, vercel] })).toThrow("ambiguous");
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "vendor/m" });
});

test("public runner upgrades a bare saved id using only the session runtime", async () => {
  const fixture = await realSessionFixture();
  const path = join(temp(), "subagent-model.json");
  saveSubagentModelConfig({ model: "m" }, path);
  const { modelRegistry: _registry, ...withoutRegistry } = fixture;
  await new WorkflowAgent({ ...withoutRegistry, subagentModelConfigPath: path }).run("bare");
  expect(fixture.seen).toEqual([{ id: "m", thinking: "low" }]);
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ model: "snapshot-test/m" });
});

test("picker keeps colon-containing ids literal and stores thinking separately", async () => {
  const saved: unknown[] = [];
  const commands = new Map<string, any>();
  registerWorkflowModelCommand({ registerCommand: (name: string, cmd: unknown) => commands.set(name, cmd) } as never, {
    load: () => null,
    save(value) { saved.push(value); },
  });
  const choices = ["2. p/pinned:high", "low"];
  await commands.get("workflow-model").handler("", {
    hasUI: true, waitForIdle: async () => {},
    scopedModels: [
      { model: { provider: "p", id: "pinned" }, thinkingLevel: "high" },
      { model: { provider: "p", id: "pinned:high" } },
    ],
    ui: { notify() {}, async select(_title: string, items: string[]) {
      const choice = choices.shift();
      expect(items).toContain(choice);
      return choice;
    } },
  });
  expect(saved).toEqual([{ model: "p/pinned:high", thinking: "low" }]);
});

test("every frozen guidance hash matches the shipped file", () => {
  for (const entry of WORKFLOW_AUTHORING_FROZEN_FILES) {
    const bytes = readFileSync(join(import.meta.dir, "../forks/pi-dynamic-workflows-safe", entry.path));
    expect(createHash("sha256").update(bytes).digest("hex")).toBe(entry.sha256);
  }
});

test("legacy journals warn before rerunning work, skip auto-resume, and acquire a model snapshot", async () => {
  const cwd = temp();
  const subagentModelConfigPath = join(temp(), "subagent-model.json");
  saveSubagentModelConfig({ model: "p/legacy" }, subagentModelConfigPath);
  const manager = new WorkflowManager({ cwd, subagentModelConfigPath, agent: { async run() { return "ok"; } } });
  const persistence = createRunPersistence(cwd);
  const installId = workflowInstallId();
  const base = {
    workflowName: "legacy", status: "paused" as const, phases: [], agents: [], logs: [],
    script: `export const meta = { name: 'legacy', description: 'test' }; return await agent('work');`,
    startedAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
    sourceStore: "global" as const, installId,
  };
  // An install-owned legacy record (no model snapshot, old journal hashes)
  // must not auto-resume: that would rerun completed work with no human aware.
  persistence.save({ ...base, runId: "legacy-auto-blocked", journal: [{ index: 0, hash: "old", result: 1 }] });
  expect(isAutoResumeEligibleRun(persistence.load("legacy-auto-blocked")!, installId)).toBe(false);
  expect(isAutoResumeEligibleRun({ ...base, runId: "no-journal" }, installId)).toBe(false);
  expect(isAutoResumeEligibleRun({ ...base, runId: "empty-journal", journal: [] }, installId)).toBe(false);
  // Control: the same record WITH a model snapshot stays auto-resume eligible.
  persistence.save({
    ...base, runId: "legacy-auto-allowed", subagentModel: "p/legacy",
    journal: [{ index: 0, hash: "new", result: 1 }],
  });
  expect(isAutoResumeEligibleRun(persistence.load("legacy-auto-allowed")!, installId)).toBe(true);

  // Explicit resume of a legacy record still works, warns, and snapshots a model.
  const runId = "legacy-model-test";
  persistence.save({ ...base, runId, journal: [{ index: 0, hash: "pre-refactor-tier-hash", result: "previous result" }] });
  const complete = Promise.withResolvers<void>();
  manager.once("complete", () => complete.resolve());
  manager.once("error", (event) => complete.reject(event.error));
  try {
    expect(await manager.resume(runId)).toBe(true);
    await complete.promise;
    expect(manager.getRun(runId)?.snapshot.logs.join("\n")).toContain("completed agents may run again");
    expect(persistence.load(runId)?.subagentModel).toBe("p/legacy");
  } finally {
    manager.deleteRun(runId);
    persistence.delete("legacy-auto-blocked");
    persistence.delete("legacy-auto-allowed");
  }
});

test("old model-only snapshots resume without reading broken current config", async () => {
  const cwd = temp();
  const path = join(temp(), "subagent-model.json");
  writeFileSync(path, "{broken");
  const persistence = createRunPersistence(cwd);
  const runId = "model-only-snapshot";
  persistence.save({ runId, workflowName: "model-only", status: "paused", phases: [], agents: [], logs: [],
    script: `export const meta = {name:'model-only', description:'test'}; return await agent('work');`,
    startedAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
    sourceStore: "global", installId: workflowInstallId(), subagentModel: "p/first" });
  const manager = new WorkflowManager({ cwd, subagentModelConfigPath: path, agent: { async run() { return "ok"; } } });
  const done = Promise.withResolvers<void>();
  manager.once("complete", () => done.resolve());
  manager.once("error", (event) => done.reject(event.error));
  try {
    expect(await manager.resume(runId)).toBe(true);
    await done.promise;
    expect(manager.getRun(runId)?.subagentModel).toBe("p/first");
    expect(manager.getRun(runId)?.subagentThinking).toBe("medium");
  } finally { manager.deleteRun(runId); }
});

test("resume keeps persisted model/thinking and replays calls even with invalid current config", async () => {
  const subagentModelConfigPath = join(temp(), "subagent-model.json");
  {
    saveSubagentModelConfig({ model: "p/first", thinking: "high" }, subagentModelConfigPath);
    const cwd = temp();
    const blocked = Promise.withResolvers<void>();
    const calls: string[] = [];
    const manager = new WorkflowManager({ cwd, subagentModelConfigPath, agent: { async run(prompt, options) {
      calls.push(prompt);
      if (prompt === "second") {
        blocked.resolve();
        await new Promise<void>((_resolve, reject) => {
          options.signal!.addEventListener("abort", () => reject(new Error("paused")), { once: true });
        });
      }
      return "ok";
    } } });
    const script = `export const meta = { name: 'resume-model', description: 'test' }; await agent('first'); return await agent('second');`;
    const { runId, promise } = manager.startInBackground(script);
    const initial = createRunPersistence(cwd).load(runId);
    expect(initial?.subagentModel).toBe("p/first");
    expect(initial?.subagentThinking).toBe("high");
    await blocked.promise;
    expect(manager.pause(runId)).toBe(true);
    await promise.catch(() => undefined);
    expect(manager.listRuns().find((run) => run.runId === runId)?.subagentModel).toBe("p/first");
    writeFileSync(subagentModelConfigPath, "{invalid json");
    const models: string[] = [];
    const resumed = new WorkflowManager({ cwd, subagentModelConfigPath, agent: { async run(prompt) { calls.push(prompt); return "ok"; } } });
    resumed.on("agentStart", (event) => models.push(event.model));
    const complete = Promise.withResolvers<void>();
    resumed.once("complete", () => complete.resolve());
    resumed.once("error", (event) => complete.reject(event.error));
    expect(await resumed.resume(runId)).toBe(true);
    await complete.promise;
    expect(resumed.getRun(runId)?.subagentModel).toBe("p/first");
    expect(resumed.getRun(runId)?.subagentThinking).toBe("high");
    expect(calls).toEqual(["first", "second", "second"]);
    expect(models.length).toBeGreaterThan(0);
    expect(models.every((m) => m === "p/first")).toBe(true);
    resumed.deleteRun(runId);
  }
});
