#!/usr/bin/env python3
"""flume-schema executor loop (reference implementation).

Drives one mock-model session end to end and writes the run log:

    python3 /app/agent_loop.py <transcript.json> <out.json>

The loop implements, in order, per model emission:
  1. shape checks      -> MALFORMED:<reason> fed back, never executed
  2. unknown tool      -> UNKNOWN_TOOL:<name> fed back
  3. schema validation -> SCHEMA_ERROR:<detail> fed back (canonical, from
                          runtime.registry), never executed
  4. idempotency       -> non-idempotent tools with an identical, already
     successfully executed call are replayed from a cache (REPLAYED:<result>),
     never re-executed; idempotent tools always re-execute
  5. execution         -> Store.execute(); retryable ToolError is retried
                          silently up to MAX_EXEC_RETRIES with exponential
                          backoff; the first non-retryable error is returned
                          as EXEC_ERROR:<code>:<detail>

The loop stops as soon as the model emits a final answer ("completed"), or
after max_steps emissions ("step_cap"), whichever comes first.  The log is a
deterministic JSON document; the grader compares it exactly against the
expected run of the same transcript.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, "/app")

from runtime.backend import Store, ToolError
from runtime.models import MockModel
from runtime.protocol import (
    EXECUTED,
    REPLAYED,
    MAX_EXEC_RETRIES,
    RETRY_BASE_DELAY_SEC,
)
from runtime.registry import ToolRegistry


def malformed_reason(emission):
    """Return the canonical MALFORMED:<reason> string, or None when the
    emission is a well-formed tool call."""
    if not isinstance(emission, dict):
        return "MALFORMED:NOT_OBJECT"
    name = emission.get("name")
    if not isinstance(name, str) or not name:
        return "MALFORMED:MISSING_NAME"
    if not isinstance(emission.get("arguments"), dict):
        return "MALFORMED:INVALID_ARGUMENTS"
    return None


def run_transcript(transcript, registry):
    store = Store(transcript)
    model = MockModel(transcript)
    executed_cache = {}
    messages = [{"role": "user", "content": transcript["user"]}]
    steps = []
    terminated = None
    max_steps = int(transcript["max_steps"])

    for step in range(1, max_steps + 1):
        emission = model.next(messages)
        entry = {"step": step, "kind": None, "tool": None, "arguments": None,
                 "outcome": None, "error": None, "retries": 0, "result": None}

        if isinstance(emission, dict) and emission.get("kind") == "final":
            entry["kind"] = "final"
            entry["outcome"] = "final"
            entry["answer"] = emission.get("answer")
            steps.append(entry)
            terminated = "completed"
            break

        entry["kind"] = "tool_call"

        # Shape checks come FIRST: a non-dict emission (or one missing its
        # name or arguments) must never be executed, and it must not crash
        # the loop.  Only well-formed tool calls carry tool/arguments into
        # the log.
        reason = malformed_reason(emission)
        if reason is not None:
            entry["outcome"] = "malformed"
            entry["error"] = reason
            if isinstance(emission, dict):
                entry["tool"] = emission.get("name")
                entry["arguments"] = emission.get("arguments")
            steps.append(entry)
            messages.append({"role": "tool", "content": reason})
            continue

        name = emission["name"]
        args = emission["arguments"]
        entry["tool"] = name
        entry["arguments"] = args

        if name not in registry.names():
            entry["outcome"] = "unknown_tool"
            entry["error"] = "UNKNOWN_TOOL:%s" % name
            steps.append(entry)
            messages.append({"role": "tool", "content": entry["error"]})
            continue

        schema_error = registry.validate(name, args)
        if schema_error is not None:
            entry["outcome"] = "schema_error"
            entry["error"] = schema_error
            steps.append(entry)
            messages.append({"role": "tool", "content": schema_error})
            continue

        cache_key = (name, json.dumps(args, sort_keys=True))
        if not registry.is_idempotent(name) and cache_key in executed_cache:
            entry["outcome"] = "replayed"
            entry["result"] = executed_cache[cache_key]
            steps.append(entry)
            payload = json.dumps(entry["result"], sort_keys=True)
            messages.append({"role": "tool", "content": REPLAYED + ":" + payload})
            continue

        result = None
        last_error = None
        failed = 0
        executed = False
        for attempt in range(MAX_EXEC_RETRIES + 1):
            if attempt:
                time.sleep(RETRY_BASE_DELAY_SEC * (2 ** (attempt - 1)))
            try:
                result = store.execute(name, args)
                entry["retries"] = attempt
                executed = True
                break
            except ToolError as exc:
                last_error = exc
                failed += 1
                if not exc.retryable:
                    break

        if executed:
            entry["outcome"] = "executed"
            entry["result"] = result
            executed_cache[cache_key] = result
            steps.append(entry)
            payload = json.dumps(result, sort_keys=True)
            messages.append({"role": "tool", "content": EXECUTED + ":" + payload})
        else:
            # retries records the number of silently retried attempts
            entry["outcome"] = "error"
            entry["retries"] = max(0, failed - 1)
            entry["error"] = "EXEC_ERROR:%s" % last_error.canonical()
            steps.append(entry)
            messages.append({"role": "tool", "content": entry["error"]})
    else:
        terminated = "step_cap"

    if terminated is None:
        terminated = "step_cap"

    return {
        "session": transcript["session"],
        "terminated": terminated,
        "steps": steps,
        "final_state": store.snapshot(),
    }


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: agent_loop.py <transcript.json> <out.json>")
    transcript_path, out_path = sys.argv[1], sys.argv[2]
    transcript = json.load(open(transcript_path, "r"))
    registry = ToolRegistry()
    report = run_transcript(transcript, registry)
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print("run complete: session=%s terminated=%s steps=%d"
          % (report["session"], report["terminated"], len(report["steps"])))


if __name__ == "__main__":
    main()