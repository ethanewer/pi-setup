import { expect, test } from "bun:test";
import { fileURLToPath } from "node:url";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const python = String.raw`
import json, runpy, sys
from pathlib import Path
module = runpy.run_path("bin/convert-pi-traces")
claude_path, codex_path, pi_path, junk_path = sys.argv[1:5]

def conv(kind, path):
    events = module["parse_session_file"](Path(path))
    if kind == "claude":
        row, reason = module["convert_claude_session"](events, path, "")
    else:
        row, reason = module["convert_codex_session"](events, path, "")
    return {
        "row": row,
        "reason": reason,
        "smoke": module["smoke_drop_reason"](row) if row else "no-row",
        "sanitize_record": module["sanitize_newline_reasoning"](row)[1] if row else "no-row",
    }

out = {
    "classify": {
        "claude": module["classify_trace_file"](Path(claude_path)),
        "codex": module["classify_trace_file"](Path(codex_path)),
        "pi": module["classify_trace_file"](Path(pi_path)),
        "junk": module["classify_trace_file"](Path(junk_path)),
    },
    "claude": conv("claude", claude_path),
    "codex": conv("codex", codex_path),
}

# Eval-results cwd filter: sessions recorded inside an eval results tree are
# benchmark rollouts for every converter (defense in depth).
EVAL_CWD = "/Users/x/pi-setup/evals/monitor/results/run1/t1/work"
claude_ev = [
    {"type": "user", "sessionId": "s1", "cwd": EVAL_CWD, "timestamp": "2026-09-09T00:00:00Z",
     "message": {"role": "user", "content": "do the task"}},
    {"type": "assistant", "sessionId": "s1", "cwd": EVAL_CWD,
     "message": {"role": "assistant", "model": "z-ai/glm-5.3-flash", "provider": "StreamLake",
                 "content": [{"type": "text", "text": "done"}], "usage": {"input_tokens": 5, "output_tokens": 1}}},
]
codex_ev = [
    {"type": "session_meta", "payload": {"id": "s2", "cwd": EVAL_CWD, "timestamp": "2026-09-09T00:00:00Z",
                                          "model_provider": "openrouter"}},
    {"type": "turn_context", "payload": {"model": "z-ai/glm-5.3-flash"}},
    {"type": "response_item", "payload": {"type": "message", "role": "assistant",
                                           "content": [{"type": "output_text", "text": "done"}]}},
]
pi_ev = [
    {"type": "session", "version": 3, "id": "s3", "timestamp": "2026-09-09T00:00:00Z",
     "cwd": "/Users/x/pi-setup/evals/browser/results/run2/t2/work"},
    {"type": "message", "message": {"role": "assistant", "provider": "openrouter",
                                     "model": "z-ai/glm-5.3-flash",
                                     "content": [{"type": "text", "text": "done"}]}},
]
out["eval_cwd"] = {
    "claude": module["convert_claude_session"](claude_ev, "x", "")[1],
    "codex": module["convert_codex_session"](codex_ev, "x", "")[1],
    "pi": module["convert_session"](pi_ev, "x", "")[1],
}

# Closed/mixed lane routing for codex rollouts (bugbot finding, 2026-09-10):
# per-turn model tracking must drop mixed sessions from BOTH lanes and route
# all-closed sessions to the closed lane only under include_closed.
def codex_rollout(models):
    ev = [{"type": "session_meta", "payload": {"id": "lane1", "cwd": "/tmp/w",
           "timestamp": "2026-09-09T00:00:00Z", "model_provider": "openrouter"}}]
    for i, mdl in enumerate(models):
        ev.append({"type": "turn_context", "payload": {"model": mdl}})
        ev.append({"type": "response_item", "payload": {"type": "reasoning",
                   "content": [{"type": "reasoning_text", "text": f"t{i}"}]}})
        ev.append({"type": "response_item", "payload": {"type": "function_call",
                   "name": "shell", "arguments": "{}", "call_id": f"c{i}"}})
        ev.append({"type": "response_item", "payload": {"type": "function_call_output",
                   "call_id": f"c{i}", "output": "ok"}})
    ev.append({"type": "response_item", "payload": {"type": "message", "role": "assistant",
               "content": [{"type": "output_text", "text": "done"}]}})
    return ev

mixed = codex_rollout(["gpt-5.6-luna", "z-ai/glm-5.3-flash"])
allclosed = codex_rollout(["gpt-5.6-luna", "gpt-5.6-luna"])
mixed_row, mixed_reason = module["convert_codex_session"](mixed, "x", "")
mixed_row_c, mixed_reason_c = module["convert_codex_session"](mixed, "x", "", include_closed=True)
closed_row, closed_reason = module["convert_codex_session"](allclosed, "x", "")
closed_row_c, closed_reason_c = module["convert_codex_session"](allclosed, "x", "", include_closed=True)
out["lanes"] = {
    "mixed_open": mixed_reason,
    "mixed_closed_flag": mixed_reason_c,
    "allclosed_open": closed_reason,
    "allclosed_closed_flag": closed_reason_c,
    "allclosed_lane": (closed_row_c or {}).get("model_lane"),
    "allclosed_turns": ((closed_row_c or {}).get("api_exchange_count")),
}

# Anthropic mixed sessions must drop from both lanes too (measurement review
# round 2): closed == OpenAI OR Anthropic, per TRACE-DATASET.md.
def asst(model, provider):
    return {"type": "message", "message": {"role": "assistant", "provider": provider,
            "model": model, "content": [{"type": "text", "text": "x"}],
            "usage": {"input": 10, "output": 5}}}

mixed_anthropic_pi = [
    {"type": "session", "version": 3, "id": "ma1", "timestamp": "2026-09-09T00:00:00Z", "cwd": "/tmp/w"},
    {"type": "message", "message": {"role": "user", "content": [{"type": "text", "text": "do work"}]}},
    asst("claude-sonnet-4", "anthropic"),
    {"type": "model_change", "provider": "openrouter", "modelId": "z-ai/glm-5.3-flash"},
    asst("z-ai/glm-5.3-flash", "openrouter"),
]
mixed_anthropic_claude = [
    {"type": "user", "sessionId": "ma2", "cwd": "/tmp/w", "timestamp": "2026-09-09T00:00:00Z",
     "message": {"role": "user", "content": "do work"}},
    {"type": "assistant", "sessionId": "ma2", "message": {"role": "assistant", "model": "claude-sonnet-4",
     "provider": "anthropic", "content": [{"type": "text", "text": "x"}], "usage": {"input_tokens": 5, "output_tokens": 2}}},
    {"type": "assistant", "sessionId": "ma2", "message": {"role": "assistant", "model": "z-ai/glm-5.3-flash",
     "provider": "StreamLake", "content": [{"type": "text", "text": "y"}], "usage": {"input_tokens": 5, "output_tokens": 2}}},
]
out["anthropic_mixed"] = {
    "pi": module["convert_session"](mixed_anthropic_pi, "x", "")[1],
    "pi_closed_flag": module["convert_session"](mixed_anthropic_pi, "x", "", include_closed=True)[1],
    "claude": module["convert_claude_session"](mixed_anthropic_claude, "x", "")[1],
    "claude_closed_flag": module["convert_claude_session"](mixed_anthropic_claude, "x", "", include_closed=True)[1],
}

# local_shell_call pairs its function_call_output by call_id (measurement
# review round 3): the adapter must not fall back to a possibly-absent id.
lsc_ev = [
    {"type": "session_meta", "payload": {"id": "lsc1s", "cwd": "/tmp/w",
     "timestamp": "2026-09-09T00:00:00Z", "model_provider": "openrouter"}},
    {"type": "turn_context", "payload": {"model": "z-ai/glm-5.3-flash"}},
    {"type": "response_item", "payload": {"type": "local_shell_call",
     "call_id": "lsc1", "action": {"command": ["ls", "-la"]}}},
    {"type": "response_item", "payload": {"type": "function_call_output",
     "call_id": "lsc1", "output": "total 0"}},
    {"type": "response_item", "payload": {"type": "message", "role": "assistant",
     "content": [{"type": "output_text", "text": "listed"}]}},
]
lsc_row, lsc_reason = module["convert_codex_session"](lsc_ev, "x", "")
# no base_instructions in this fixture -> no system message: [assistant, tool, assistant]
out["local_shell"] = {
    "reason": lsc_reason,
    "call_id": (lsc_row["messages"][0].get("tool_calls") or [{}])[0].get("id"),
    "result_id": lsc_row["messages"][1].get("tool_call_id"),
    "result_text": lsc_row["messages"][1].get("content"),
}

# monitor-bench ingest must skip non-pi harness runs (their t5 control runs
# would otherwise publish as harness:"pi" rows).
out["monitor_meta"] = {
    "pi": module["monitor_meta_is_pi"]({"harness": "pi"}),
    "legacy": module["monitor_meta_is_pi"]({}),
    "p": module["monitor_meta_is_pi"]({"harness": "p"}),
    "occ": module["monitor_meta_is_pi"]({"harness": "occ"}),
    "ocdx": module["monitor_meta_is_pi"]({"harness": "ocdx"}),
}
print(json.dumps(out))
`;

function pythonBin(): string {
	for (const bin of ["python3", "python"]) {
		if (Bun.spawnSync([bin, "--version"]).error === undefined) return bin;
	}
	throw new Error("neither python3 nor python is runnable");
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function claudeFixture(): object[] {
	return [
		{ type: "summary", summary: "Bug fix session", leafUuid: "a2" },
		{
			type: "user", sessionId: "occ-sess-1", cwd: "/tmp/proj",
			timestamp: "2026-09-09T01:00:00.000Z", version: "2.0.0", gitBranch: "main",
			uuid: "u1", parentUuid: null, isSidechain: false, userType: "external",
			message: { role: "user", content: "Please fix the bug in app.py" },
		},
		{
			type: "user", isMeta: true, sessionId: "occ-sess-1", uuid: "um1", isSidechain: false,
			message: { role: "user", content: [{ type: "text", text: "<command-name>/model</command-name>" }] },
		},
		{
			type: "assistant", sessionId: "occ-sess-1", cwd: "/tmp/proj",
			timestamp: "2026-09-09T01:00:05.000Z", uuid: "a1", isSidechain: false,
			message: {
				role: "assistant", model: "z-ai/glm-5.3-flash", provider: "StreamLake",
				content: [
					{ type: "thinking", thinking: "Line one.\nLine two with app.py", signature: "" },
					{ type: "tool_use", id: "call_1", name: "Read", input: { path: "app.py", offset: 1 } },
					{
						type: "tool_use", id: "call_2", name: "Bash",
						input: { command: "pytest -q", nested: { deep: [1, 2, { k: "v" }] } },
					},
				],
				usage: {
					input_tokens: 100, cache_read_input_tokens: 50, cache_creation_input_tokens: 0,
					output_tokens: 40, output_tokens_details: { thinking_tokens: 17 },
				},
			},
		},
		{
			type: "user", sessionId: "occ-sess-1", uuid: "u2", isSidechain: false,
			timestamp: "2026-09-09T01:00:06.000Z",
			message: {
				role: "user",
				content: [
					{ type: "tool_result", tool_use_id: "call_1", content: "def f(): ..." },
					{ type: "tool_result", tool_use_id: "call_2", content: "FAIL", is_error: true },
					{ type: "text", text: "Also check the logs." },
				],
			},
		},
		{
			type: "assistant", sessionId: "occ-sess-1", uuid: "a1s", isSidechain: true,
			message: {
				role: "assistant", model: "z-ai/glm-5.3-flash", provider: "StreamLake",
				content: [{ type: "text", text: "subagent chatter that must be skipped" }],
				usage: { input_tokens: 999, output_tokens: 999 },
			},
		},
		{
			type: "assistant", sessionId: "occ-sess-1", cwd: "/tmp/proj",
			timestamp: "2026-09-09T01:00:09.000Z", uuid: "a2", isSidechain: false,
			message: {
				role: "assistant", model: "z-ai/glm-5.3-flash", provider: "Wafer",
				content: [
					{ type: "thinking", thinking: "Fixed it." },
					{ type: "text", text: "Done." },
				],
				usage: {
					input_tokens: 200, cache_read_input_tokens: 0, cache_creation_input_tokens: 0,
					output_tokens: 30, output_tokens_details: { thinking_tokens: 8 },
				},
			},
		},
		{
			// Assistant line WITHOUT usage: must not inherit the previous turn's
			// reasoning_tokens (bugbot finding, round 4).
			type: "assistant", sessionId: "occ-sess-1", cwd: "/tmp/proj",
			timestamp: "2026-09-09T01:00:12.000Z", uuid: "a3", isSidechain: false,
			message: {
				role: "assistant", model: "z-ai/glm-5.3-flash", provider: "Wafer",
				content: [{ type: "text", text: "Anything else?" }],
			},
		},
	];
}

function codexFixture(): object[] {
	return [
		{
			timestamp: "2026-09-09T19:00:00.000Z", ordinal: 0, type: "session_meta",
			payload: {
				id: "codex-sess-1", session_id: "codex-sess-1",
				timestamp: "2026-09-09T19:00:00.000Z", cwd: "/tmp/proj",
				cli_version: "0.153.4", model_provider: "openrouter",
				base_instructions: { text: "You are Codex, a coding agent." },
			},
		},
		{ type: "turn_context", payload: { model: "moonshotai/kimi-k3", cwd: "/tmp/proj" } },
		{
			type: "response_item",
			payload: { type: "message", role: "user", content: [{ type: "input_text", text: "List files then summarize." }] },
		},
		{
			type: "response_item",
			payload: {
				type: "reasoning",
				summary: [{ type: "summary_text", text: "Sum first." }],
				content: [{ type: "reasoning_text", text: "Then call shell." }],
			},
		},
		{
			type: "response_item",
			payload: { type: "function_call", name: "shell", arguments: "{\"command\":[\"ls\",\"-la\"]}", call_id: "fc_1" },
		},
		{
			type: "response_item",
			payload: { type: "function_call", name: "read_file", arguments: "{\"path\":\"README.md\"}", call_id: "fc_2" },
		},
		{
			type: "response_item",
			payload: { type: "function_call_output", call_id: "fc_1", output: "total 8\ndrwx" },
		},
		{
			type: "response_item",
			payload: { type: "function_call_output", call_id: "fc_2", output: { content: [{ type: "output_text", text: "# Hi" }] } },
		},
		{
			type: "token_usage_record",
			payload: {
				turn_token_usage: {
					input_tokens: 1000, cached_input_tokens: 0, output_tokens: 55,
					reasoning_output_tokens: 12, total_tokens: 1055,
				},
			},
		},
		{ type: "event_msg", payload: { type: "item_completed", item: { type: "duplicated-noise" } } },
		{
			type: "response_item",
			payload: { type: "reasoning", summary: [], content: [{ type: "reasoning_text", text: "Wrap up." }] },
		},
		{
			type: "response_item",
			payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "Two files." }] },
		},
		{
			type: "token_usage_record",
			payload: {
				turn_token_usage: {
					input_tokens: 1100, output_tokens: 20,
					reasoning_output_tokens: 5, total_tokens: 1120,
				},
			},
		},
	];
}

function runAdapters() {
	const dir = mkdtempSync(join(tmpdir(), "trace-adapters-"));
	const claudePath = join(dir, "occ.jsonl");
	const codexPath = join(dir, "rollout.jsonl");
	const piPath = join(dir, "pi.jsonl");
	const junkPath = join(dir, "junk.jsonl");
	const writeJsonl = (p: string, lines: object[]) =>
		writeFileSync(p, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	writeJsonl(claudePath, claudeFixture());
	writeJsonl(codexPath, codexFixture());
	writeJsonl(piPath, [
		{ type: "session", version: 3, id: "p1", timestamp: "2026-09-09T00:00:00.000Z", cwd: "/tmp" },
	]);
	writeJsonl(junkPath, [{ hello: "world" }, { type: "message", message: { role: "user" } }]);

	const result = Bun.spawnSync(
		[pythonBin(), "-c", python, claudePath, codexPath, piPath, junkPath],
		{ cwd: fileURLToPath(new URL("..", import.meta.url)) },
	);
	expect(result.exitCode).toBe(0);
	return JSON.parse(result.stdout.toString());
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test("classify_trace_file detects pi, occ (claude), ocdx (codex), and rejects junk", () => {
	const { classify } = runAdapters();
	expect(classify.claude).toBe("claude");
	expect(classify.codex).toBe("codex");
	expect(classify.pi).toBe("pi");
	expect(classify.junk).toBeNull();
});

test("sessions recorded inside eval results trees are dropped as benchmark rollouts", () => {
	const { eval_cwd } = runAdapters();
	expect(eval_cwd.claude).toBe("benchmark_rollout");
	expect(eval_cwd.codex).toBe("benchmark_rollout");
	expect(eval_cwd.pi).toBe("benchmark_rollout");
});

test("codex lane routing: mixed open/closed dropped from both lanes, all-closed only under include_closed", () => {
	const { lanes } = runAdapters();
	expect(lanes.mixed_open).toBe("model:mixed-closed");
	expect(lanes.mixed_closed_flag).toBe("model:mixed-closed");
	expect(lanes.allclosed_open).toBe("openai");
	expect(lanes.allclosed_closed_flag).toBe("");
	expect(lanes.allclosed_lane).toBe("openai");
	expect(lanes.allclosed_turns).toBe(3);
});

test("mixed Anthropic+open sessions are dropped from both lanes in every converter", () => {
	const { anthropic_mixed } = runAdapters();
	expect(anthropic_mixed.pi).toBe("model:mixed-closed");
	expect(anthropic_mixed.pi_closed_flag).toBe("model:mixed-closed");
	expect(anthropic_mixed.claude).toBe("model:mixed-closed");
	expect(anthropic_mixed.claude_closed_flag).toBe("model:mixed-closed");
});

test("codex local_shell_call pairs its output by call_id", () => {
	const { local_shell } = runAdapters();
	expect(local_shell.reason).toBe("");
	expect(local_shell.call_id).toBe("lsc1");
	expect(local_shell.result_id).toBe("lsc1");
	expect(local_shell.result_text).toBe("total 0");
});

test("monitor-bench ingest accepts only pi-harness runs (legacy metas count as pi)", () => {
	const { monitor_meta } = runAdapters();
	expect(monitor_meta.pi).toBe(true);
	expect(monitor_meta.legacy).toBe(true);
	expect(monitor_meta.p).toBe(false);
	expect(monitor_meta.occ).toBe(false);
	expect(monitor_meta.ocdx).toBe(false);
});

test("occ adapter preserves reasoning, tool calls, results, errors, and usage", () => {
	const { claude } = runAdapters();
	expect(claude.reason).toBe("");
	expect(claude.smoke).toBeNull();
	expect(claude.sanitize_record).toBeNull();
	const row = claude.row;
	expect(row).not.toBeNull();

	// Identity / lane fields.
	expect(row.trace_key).toBe("occ-session:occ-sess-1");
	expect(row.source).toBe("local/occ");
	expect(row.harness).toBe("claude-code");
	expect(row.agent).toBe("claude-code");
	expect(row.model).toBe("z-ai/glm-5.3-flash");
	expect(row.model_provider).toBe("openrouter");
	expect(row.date).toBe("2026-09-09");
	expect(row.description).toBe("Please fix the bug in app.py");
	expect(row.model_lane).toBeUndefined();

	// Message structure: user, assistant, tool, tool, user, assistant, assistant.
	// Sidechain and isMeta lines are skipped; the summary line is ignored.
	// Text accompanying tool results on one line survives as its own user
	// message after the tool results (bugbot finding, 2026-09-10).
	expect(row.messages.map((m: any) => m.role)).toEqual(["user", "assistant", "tool", "tool", "user", "assistant", "assistant"]);

	// Reasoning is preserved verbatim, newlines included.
	expect(row.messages[1].reasoning_content).toBe("Line one.\nLine two with app.py");
	expect(row.messages[1].reasoning_status).toBe("present");
	expect(row.messages[1].reasoning_tokens).toBe(17);
	expect(row.messages[4].content).toEqual([{ type: "text", text: "Also check the logs." }]);
	expect(row.messages[5].reasoning_content).toBe("Fixed it.");
	expect(row.messages[5].content).toBe("Done.");
	// The no-usage assistant line keeps its text but inherits no reasoning_tokens.
	expect(row.messages[6].content).toBe("Anything else?");
	expect(row.messages[6].reasoning_tokens).toBeUndefined();

	// Every tool call survives with full (nested) arguments and ids.
	expect(row.messages[1].tool_calls).toEqual([
		{ id: "call_1", type: "function", function: { name: "Read", arguments: { path: "app.py", offset: 1 } } },
		{
			id: "call_2", type: "function",
			function: { name: "Bash", arguments: { command: "pytest -q", nested: { deep: [1, 2, { k: "v" }] } } },
		},
	]);
	expect(row.tools).toEqual(["Bash", "Read"]);

	// Tool results are paired by id; the error result surfaces as the exception.
	expect(row.messages[2]).toEqual({ role: "tool", content: "def f(): ...", tool_call_id: "call_1" });
	expect(row.messages[3]).toEqual({ role: "tool", content: "FAIL", tool_call_id: "call_2" });
	expect(row.exception_message).toBe("FAIL");
	expect(row.exception_type).toBe("tool_error");

	// Usage math: inputs include cache reads; completion sums outputs. The
	// third assistant line carries no usage, so accounting is incomplete.
	expect(row.api_exchange_count).toBe(3);
	expect(row.prompt_tokens).toBe(150);
	expect(row.completion_tokens).toBe(70);
	expect(row.total_tokens).toBe(220);
	expect(row.api_usage_complete).toBe(false);
	expect(row.token_accounting).toBe("estimated");

	// Provenance metadata.
	expect(row.source_metadata.harness_profile).toBe("occ");
	expect(row.source_metadata.openrouter_vendors).toEqual(["StreamLake", "Wafer"]);
	expect(row.source_metadata.sidechain_lines_skipped).toBe(1);
	expect(row.source_metadata.meta_lines_skipped).toBe(1);
	expect(row.source_metadata.claude_cli_version).toBe("2.0.0");
	expect(row.source_metadata.git_branch).toBe("main");
});

test("ocdx adapter preserves the system prompt, reasoning, tool calls, results, and usage", () => {
	const { codex } = runAdapters();
	expect(codex.reason).toBe("");
	expect(codex.smoke).toBeNull();
	expect(codex.sanitize_record).toBeNull();
	const row = codex.row;
	expect(row).not.toBeNull();

	// Identity / lane fields.
	expect(row.trace_key).toBe("ocdx-session:codex-sess-1");
	expect(row.source).toBe("local/ocdx");
	expect(row.harness).toBe("codex");
	expect(row.agent).toBe("codex");
	expect(row.model).toBe("moonshotai/kimi-k3");
	expect(row.model_provider).toBe("openrouter");
	expect(row.date).toBe("2026-09-09");
	expect(row.model_lane).toBeUndefined();

	// base_instructions are persisted by codex and emitted as a system message.
	expect(row.messages.map((m: any) => m.role)).toEqual(["system", "user", "assistant", "tool", "tool", "assistant"]);
	expect(row.messages[0].content).toEqual([{ type: "text", text: "You are Codex, a coding agent." }]);
	expect(row.source_metadata.system_prompt_persisted).toBe(true);
	expect(row.source_metadata.codex_cli_version).toBe("0.153.4");

	// Turn 1: summary + reasoning_text joined verbatim; both calls with parsed args.
	expect(row.messages[2].reasoning_content).toBe("Sum first.\nThen call shell.");
	expect(row.messages[2].reasoning_status).toBe("present");
	expect(row.messages[2].tool_calls).toEqual([
		{ id: "fc_1", type: "function", function: { name: "shell", arguments: { command: ["ls", "-la"] } } },
		{ id: "fc_2", type: "function", function: { name: "read_file", arguments: { path: "README.md" } } },
	]);
	expect(row.tools).toEqual(["read_file", "shell"]);

	// Outputs: plain string and {content:[...]} forms both extracted, paired by call_id.
	expect(row.messages[3]).toEqual({ role: "tool", content: "total 8\ndrwx", tool_call_id: "fc_1" });
	expect(row.messages[4]).toEqual({ role: "tool", content: "# Hi", tool_call_id: "fc_2" });

	// Turn 2: event_msg noise ignored; final assistant text kept.
	expect(row.messages[5].reasoning_content).toBe("Wrap up.");
	expect(row.messages[5].content).toBe("Two files.");
	expect(row.messages[5].tool_calls).toBeUndefined();

	// reasoning_tokens backfilled from per-turn token_usage_record ordinals.
	expect(row.messages[2].reasoning_tokens).toBe(12);
	expect(row.messages[5].reasoning_tokens).toBe(5);

	// Usage math.
	expect(row.api_exchange_count).toBe(2);
	expect(row.prompt_tokens).toBe(1000);
	expect(row.completion_tokens).toBe(75);
	expect(row.total_tokens).toBe(1075);
	expect(row.api_total_tokens).toBe(1120);
	expect(row.api_usage_complete).toBe(true);
});
