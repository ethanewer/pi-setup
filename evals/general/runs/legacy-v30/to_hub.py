#!/usr/bin/env python3
"""Normalize general-eval traces for HF eewer/general-agent-bench-results v3.0.

For each merged record in final/<run>/<agent>/<task>/, emit:
  hub/v3.0/<agent>/<model>/<task>/trajectory.json  normalized messages with
                                                   reasoning_content, tool_calls,
                                                   and tool definitions
  hub/v3.0/<agent>/<model>/<task>/metadata.json    task/agent/model/reward/etc
  hub/v3.0/<agent>/<model>/<task>/verifier/        reward.txt, test-stdout.txt
  hub/v3.0/<agent>/<model>/results.json            per-run score table
  hub/v3.0/summary.json                            all six runs
"""
import importlib.util, json, re, shutil, sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

FINAL = Path("/home/ee/general-eval-runs/final")
HUB = Path("/home/ee/general-eval-runs/hub/v3.0")

def load_pi_converter():
    loader = SourceFileLoader("cptr", "/home/ee/pi-setup/bin/convert-pi-traces")
    spec = importlib.util.spec_from_loader("cptr", loader)
    m = importlib.util.module_from_spec(spec)
    sys.modules["cptr"] = m
    loader.exec_module(m)
    return m

CPTR = load_pi_converter()

# ---------------------------------------------------------------- tool defs
PI_TOOLS = [
    {"type": "function", "function": {"name": "bash", "description":
        "Execute a shell command in the working directory; returns stdout/stderr.",
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string", "description": "Shell command to execute"},
            "timeout": {"type": "number", "description": "Optional timeout in seconds"}},
            "required": ["command"]}}},
    {"type": "function", "function": {"name": "read", "description":
        "Read the contents of a text file (or image).",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "offset": {"type": "number", "description": "1-indexed line offset"},
            "limit": {"type": "number", "description": "Max lines to read"}},
            "required": ["path"]}}},
    {"type": "function", "function": {"name": "write", "description":
        "Write content to a file, creating it (and parent dirs) if needed.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"]}}},
    {"type": "function", "function": {"name": "edit", "description":
        "Edit a file via exact text replacement; each oldText must match uniquely.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "edits": {"type": "array", "items": {"type": "object", "properties": {
                "oldText": {"type": "string"}, "newText": {"type": "string"}},
                "required": ["oldText", "newText"]}}},
            "required": ["path", "edits"]}}},
]

TERMINUS_TOOLS = [
    {"type": "function", "function": {"name": "bash_command", "description":
        "Send keystrokes to the task's tmux terminal (terminus-2 protocol: the "
        "model replies with JSON {analysis, plan, commands}; harbor renders each "
        "command as one bash_command call).",
        "parameters": {"type": "object", "properties": {
            "keystrokes": {"type": "string", "description": "Keystrokes to send (include \\n to run)"},
            "duration": {"type": "number", "description": "Seconds to wait after sending"}},
            "required": ["keystrokes"]}}},
    {"type": "function", "function": {"name": "mark_task_complete", "description":
        "Signal that the task is complete; terminates the terminus-2 episode.",
        "parameters": {"type": "object", "properties": {
            "reasoning": {"type": "string", "description": "Why the task is complete"}},
            "required": ["reasoning"]}}},
]

CLAUDE_TOOL_DESCRIPTIONS = {
    "Bash": "Execute a shell command in the working directory.",
    "Read": "Read the contents of a file.",
    "Write": "Write content to a file (creates or overwrites).",
    "Edit": "Replace an exact string occurrence in a file.",
    "MultiEdit": "Apply multiple ordered string replacements to a file.",
    "Glob": "Find files matching a glob pattern.",
    "Grep": "Search file contents with a regex pattern.",
    "WebFetch": "Fetch a URL and process the content.",
    "WebSearch": "Search the web.",
    "Task": "Launch a sub-agent task.",
    "NotebookEdit": "Edit a Jupyter notebook cell.",
    "TodoWrite": "Create/update the task todo list.",
}

def claude_tools(names):
    return [{"type": "function", "function": {
        "name": n,
        "description": CLAUDE_TOOL_DESCRIPTIONS.get(n, f"Claude Code built-in tool: {n}"),
        "parameters": {"type": "object", "properties": {},
                       "additionalProperties": True}}} for n in names]

# ---------------------------------------------------------------- pi traces
def pi_trajectory(agent_dir: Path, task: str, model: str) -> dict | None:
    sess = sorted((agent_dir / "pi" / "sessions").glob("*.jsonl")) if (agent_dir / "pi" / "sessions").is_dir() else []
    events = []
    for f in sess:
        try:
            ev = [json.loads(l) for l in f.read_text().splitlines() if l.strip()]
        except Exception:
            continue
        if ev and ev[0].get("type") == "session":
            events.extend(ev)
    if not events:
        return None
    messages, meta = CPTR.convert_messages(events)
    if not messages:
        return None
    tools_used = sorted({tc["function"]["name"] for m in messages
                         for tc in (m.get("tool_calls") or [])
                         if tc.get("function", {}).get("name")})
    return {
        "agent": "pi", "agent_profile": "p (lean: no extensions, no skills)",
        "agent_version": "pi 0.84.3 (patched)",
        "model": model, "task": task,
        "tools": PI_TOOLS, "tools_used": tools_used,
        "messages": messages,
        "usage": {"assistant_turns": meta.get("assistant_turns"),
                  "prompt_tokens_first_input": (meta.get("usage_inputs") or [None])[0],
                  "output_tokens": sum(meta.get("usage_outputs") or []),
                  "final_total_tokens": (meta.get("usage_total") or [None])[-1]},
    }

# ------------------------------------------------------------- ATIF (terminus + claude)
def _terminus_reasoning_fallback(text: str) -> str | None:
    """Analysis/Plan text in terminus messages is reasoning when the ATIF
    step has no reasoning_content of its own."""
    if not text:
        return None
    low = text.lstrip().lower()
    if low.startswith("analysis:") or low.startswith("plan:"):
        return text
    return None

def atif_trajectory(agent_dir: Path, task: str, model: str, agent: str,
                    tools: list, extra: dict | None = None) -> dict | None:
    tj = agent_dir / "trajectory.json"
    if not tj.exists():
        return None
    d = json.loads(tj.read_text())
    steps = d.get("steps", [])
    tool_names = []
    if agent == "claude-code":
        cc = agent_dir / "claude-code.txt"
        if cc.exists():
            for line in cc.read_text(errors="replace").splitlines()[:5]:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if e.get("type") == "system" and e.get("subtype") == "init" and e.get("tools"):
                    tool_names = e["tools"]
                    break
    messages = []
    for st in steps:
        if st.get("source") == "user":
            messages.append({"role": "user",
                             "content": [{"type": "text", "text": st.get("message") or ""}]})
        elif st.get("source") == "agent":
            msg = {"role": "assistant", "content": st.get("message") or None}
            reasoning = st.get("reasoning_content")
            if not reasoning and agent == "terminus-2":
                reasoning = _terminus_reasoning_fallback(st.get("message") or "")
            if reasoning:
                msg["reasoning_content"] = reasoning
            calls = st.get("tool_calls") or []
            results = (st.get("observation") or {}).get("results") or []
            res_by_id = {r.get("source_call_id"): r.get("content") for r in results}
            if calls:
                tcs = []
                for i, c in enumerate(calls):
                    tcid = c.get("tool_call_id") or f"{agent}-step-{st.get('step_id')}-{i}"
                    tcs.append({"id": tcid, "type": "function",
                                "function": {"name": c.get("function_name"),
                                             "arguments": json.dumps(c.get("arguments") or {})}})
                msg["tool_calls"] = tcs
            messages.append(msg)
            for c in calls:
                tcid = c.get("tool_call_id")
                messages.append({"role": "tool",
                                 "content": str(res_by_id.get(tcid, "")),
                                 "tool_call_id": tcid})
    if not messages:
        return None
    out = {
        "agent": agent, "agent_version": d.get("agent", {}).get("version"),
        "model": model, "task": task,
        "tools": claude_tools(tool_names) if agent == "claude-code" else tools,
        "tools_used": sorted({c.get("function_name") for st in steps
                              for c in (st.get("tool_calls") or [])
                              if c.get("function_name")}),
        "messages": messages,
        "final_metrics": d.get("final_metrics"),
    }
    if agent == "pi":
        out["agent_profile"] = "p (lean: no extensions, no skills)"
    return out

CONVERTERS = {
    "pi": pi_trajectory,
    "terminus-2": lambda d, t, m: atif_trajectory(d, t, m, "terminus-2", TERMINUS_TOOLS),
    "claude-code": lambda d, t, m: atif_trajectory(d, t, m, "claude-code", []),
}

def main():
    if HUB.exists():
        shutil.rmtree(HUB)
    stats = {}
    for run_dir in sorted(FINAL.iterdir()):
        if not run_dir.is_dir():
            continue
        label = run_dir.name
        for agent_dir in run_dir.iterdir():
            agent = agent_dir.name
            if agent not in CONVERTERS:
                continue
            rewards, n_tasks, skipped = {}, 0, []
            for task_dir in sorted(agent_dir.iterdir()):
                task = task_dir.name
                md_path = task_dir / "metadata.json"
                md = json.loads(md_path.read_text()) if md_path.exists() else {}
                model = md.get("model") or "?"
                model_slug = model.removeprefix("openrouter/")
                out = HUB / agent / model_slug / task
                (out / "verifier").mkdir(parents=True, exist_ok=True)
                traj = CONVERTERS[agent](task_dir / "agent", task, model)
                if traj is None:
                    skipped.append(task)
                    traj_note = {"agent": agent, "model": model, "task": task,
                                 "note": "no trace available (trial did not produce agent logs)"}
                    (out / "trajectory.json").write_text(json.dumps(traj_note, indent=1))
                else:
                    traj["reward"] = md.get("reward")
                    traj["exception"] = bool((task_dir / "exception.txt").exists())
                    (out / "trajectory.json").write_text(json.dumps(traj, ensure_ascii=False))
                md_out = {k: md.get(k) for k in
                          ("task", "agent", "model", "reward", "agent_timeout", "source_trial")}
                if (task_dir / "exception.txt").exists():
                    md_out["exception"] = (task_dir / "exception.txt").read_text()[-2000:]
                (out / "metadata.json").write_text(json.dumps(md_out, indent=1))
                for f in ("reward.txt", "test-stdout.txt"):
                    src = task_dir / "verifier" / f
                    if src.exists():
                        shutil.copy(src, out / "verifier" / f)
                r = md.get("reward")
                rewards[task] = float(r) if r is not None else 0.0
                n_tasks += 1
            total = sum(rewards.values())
            results = {"run": label, "agent": agent, "model": model,
                       "n_tasks": n_tasks, "total_reward": round(total, 2),
                       "pass_rate_765": round(total / 765, 4),
                       "no_trace_tasks": skipped}
            (HUB / agent / model_slug / "results.json").write_text(json.dumps(results, indent=1))
            stats[label] = results
            print(f"{label}: {n_tasks} records, reward {total:.2f}, no-trace: {len(skipped)}")
    (HUB / "summary.json").write_text(json.dumps({
        "dataset": "pi-setup/evals/general @ pi-setup 1855e2db (765 tasks)",
        "harnesses": {"pi": "lean 'p' profile (no extensions/skills), pi 0.84.3 patched",
                      "terminus-2": "harbor terminus-2",
                      "claude-code": "claude-code CLI via OpenRouter Anthropic-compatible endpoint"},
        "note": "cinder-hearth (image build bug) and drift-canyon (verifier bug) are "
                "unscoreable dataset defects, counted as 0; calm-canyon fails systematically "
                "under terminus-2 (tmux/OOM) and is counted as 0. "
                "Traces: messages carry reasoning_content for reasoning turns and tool_calls "
                "paired with tool results; each record's top-level 'tools' lists the tool "
                "definitions. Episodes cut off by agent timeout end on a tool_call without a "
                "result (faithful to the raw session).",
        "runs": stats}, indent=1))
    print("staged:", HUB)

if __name__ == "__main__":
    sys.exit(main())
