import { expect, test } from "bun:test";

const python = String.raw`
import json, runpy, sys
module = runpy.run_path("bin/convert-pi-traces")
row = json.loads(sys.argv[1])
clean, record = module["sanitize_newline_reasoning"](row)
print(json.dumps({"clean": clean, "record": record}, sort_keys=True))
`;

function sanitize(row: Record<string, unknown>) {
	const result = Bun.spawnSync(["python3", "-c", python, JSON.stringify(row)], {
		cwd: new URL("..", import.meta.url).pathname,
	});
	expect(result.exitCode).toBe(0);
	return JSON.parse(result.stdout.toString());
}

function baseRow(messages: Array<Record<string, unknown>>) {
	return {
		trace_key: "pi-session:test",
		source_path: "/sessions/test.jsonl",
		messages,
		api_exchange_count: 2,
		api_completion_tokens: 100,
		api_prompt_tokens: 200,
		api_total_tokens: 300,
		completion_tokens: 100,
		prompt_tokens: 200,
		total_tokens: 300,
		api_usage_complete: true,
		token_accounting: "conversation_delta_from_api_usage",
		exception_message: "suffix error",
		exception_type: "tool_error",
		outcome: { completion_tokens: 100, prompt_tokens: 200, exception_message: "suffix error" },
		source_metadata: { host: "test" },
	};
}

const splitReasoning = "Wait —\n the\n NV\nTE environment variable is exported\n inside\n the sb\natch script";

test("newline-reasoning quarantine keeps only the clean prefix and invalidates stale accounting", () => {
	const row = baseRow([
		{ role: "user", content: [{ type: "text", text: "first" }] },
		{ role: "assistant", content: "clean", reasoning_content: "A normal thought." },
		{ role: "user", content: [{ type: "text", text: "second" }] },
		{ role: "assistant", content: "affected", reasoning_content: splitReasoning },
		{ role: "tool", content: "contaminated suffix", tool_call_id: "x" },
	]);
	const { clean, record } = sanitize(row);
	expect(clean.messages).toHaveLength(3);
	expect(clean.messages.at(-1).role).toBe("user");
	expect(clean.segment_reason).toBe("newline_reasoning_clean_prefix");
	expect(clean.api_exchange_count).toBe(1);
	expect(clean.api_usage_complete).toBe(false);
	expect(clean.total_tokens).toBe(0);
	expect(clean.exception_message).toBeNull();
	expect(clean.source_metadata.newline_reasoning_sanitization.policy).toBe(
		"pi-ai-0.84.3-newline-reasoning-v1",
	);
	expect(record.action).toBe("truncate_before_first_affected_assistant");
	expect(record.first_affected_message_index).toBe(3);
	expect(record.metrics.severe).toBe(true);

	const repeated = sanitize(clean);
	expect(repeated.clean).toEqual(clean);
	expect(repeated.record).toEqual(record);
});

test("a trace whose first assistant response is affected is excluded", () => {
	const { clean, record } = sanitize(
		baseRow([
			{ role: "user", content: [{ type: "text", text: "request" }] },
			{ role: "assistant", content: "affected", reasoning_content: splitReasoning },
		]),
	);
	expect(clean).toBeNull();
	expect(record.action).toBe("exclude_trace");
	expect(record.retained_message_count).toBe(0);
});

test("ordinary reasoning paragraphs, lists, and code layout remain byte-identical", () => {
	const reasoning = "Plan:\n\n1. Read the file\n2. Run tests\n\n```ts\nconst value = 1;\n```";
	const row = baseRow([
		{ role: "user", content: [{ type: "text", text: "request" }] },
		{ role: "assistant", content: "done", reasoning_content: reasoning },
	]);
	const { clean, record } = sanitize(row);
	expect(record).toBeNull();
	expect(clean).toEqual(row);
	expect(clean.messages[1].reasoning_content).toBe(reasoning);
});
