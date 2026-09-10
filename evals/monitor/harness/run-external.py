#!/usr/bin/env python3
"""monitor-bench external-harness adapter: runs one task headlessly through
occ (Claude Code) or ocdx (Codex CLI) instead of the pi SDK.

Produces the SAME run-dir artifacts as the pi runner (harness/run-cli.ts) so
score/score.py works unmodified:
  <RUN_DIR>/<TASK>/work/            fixture workspace (hashed before the run)
  <RUN_DIR>/<TASK>/transcript.jsonl tool_start/tool_end/turn_end events
  <RUN_DIR>/<TASK>/events.jsonl     empty (no pi-style wakeups exist here)
  <RUN_DIR>/<TASK>/run.json         metrics incl. watcherStarts=0 (no monitor)
  <RUN_DIR>/<TASK>/stream.jsonl     raw harness stdout capture

Semantics / fairness notes:
  * The monitor extension does not exist in these harnesses; watcherStarts is
    always 0, so used_monitor will be False. The interesting signal is whether
    the harness's NATIVE async mechanisms (claude run_in_background/task
    notifications, codex PTY sessions) replace blocking, and whether outcomes
    still land.
  * Tool names are normalized for the scorer. occ (claude stream-json
    tool_use): Bash -> "bash", Read -> "read", Edit -> "edit", Write ->
    "write"; other Claude tools keep their names. ocdx (codex exec --json
    items): command_execution -> "bash" (covers the exec_command and
    write_stdin PTY calls, so shell wall time is measured), file_change ->
    "edit" (apply_patch results); other items keep native names. This keeps
    bash_blocking_seconds comparable across harnesses.
  * One-shot CLIs have no quiescence/wakeup loop: when the process exits, the
    run is over. To mirror the pi harness's 25 s settle window, leftover .pid
    fixture processes are killed GRACE_S seconds after exit, not immediately.

env: TASK, RUN_DIR, SEED, HARNESS (occ|ocdx), MODEL_LABEL, MODEL_HANDLE,
     BUDGET_S (optional override)
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # evals/monitor
TASK = os.environ.get("TASK", "t1")
RUN_DIR = Path(os.environ.get("RUN_DIR") or (ROOT / "results" / "dev-external")).resolve()
SEED = os.environ.get("SEED", "0")
HARNESS = os.environ.get("HARNESS", "")
MODEL_LABEL = os.environ.get("MODEL_LABEL", "openrouter/z-ai/glm-5.3-flash")
MODEL_HANDLE = os.environ.get("MODEL_HANDLE", "glm-flash")

BUDGETS = {"t1": 720, "t2": 720, "t3": 600, "t4": 720, "t5": 300, "t6": 480, "t7": 540}
BUDGET_S = int(os.environ.get("BUDGET_S") or BUDGETS.get(TASK, 600))
GRACE_S = 25  # mirrors the pi harness's quiescence window before killing pids

if HARNESS not in ("occ", "ocdx"):
    print(f"HARNESS must be occ or ocdx (got {HARNESS!r})", file=sys.stderr)
    sys.exit(2)

# ---------------------------------------------------------------- workspace
task_dir = ROOT / "tasks" / TASK
run_dir = RUN_DIR / TASK
work_dir = run_dir / "work"
if run_dir.exists():
    shutil.rmtree(run_dir)
work_dir.mkdir(parents=True)
shutil.copytree(str(task_dir / "fixture"), str(work_dir), dirs_exist_ok=True)


def hash_tree(d: Path, base: Path, out: dict) -> None:
    for p in sorted(d.iterdir()):
        rel = str(p.relative_to(base))
        if p.is_dir():
            hash_tree(p, base, out)
        else:
            out[rel] = hashlib.sha256(p.read_bytes()).hexdigest()


fixture_hashes: dict = {}
hash_tree(work_dir, work_dir, fixture_hashes)

prompt = (task_dir / "prompt.txt").read_text()
nonce = os.urandom(6).hex()
s = socket.socket()
s.bind(("127.0.0.1", 0))
mb_port = s.getsockname()[1]
s.close()

env = dict(os.environ)
env.update({
    "SEED": SEED,
    "MB_NONCE": nonce,
    "MB_PORT": str(mb_port),
    "PYTHONUNBUFFERED": "1",
})

transcript_path = run_dir / "transcript.jsonl"
events_path = run_dir / "events.jsonl"
stream_path = run_dir / "stream.jsonl"
harness_log = run_dir / "harness.log"
events_path.write_text("")  # exists but empty: no wakeup semantics in one-shot CLIs


def log(msg: str) -> None:
    with open(harness_log, "a") as f:
        f.write(f"{datetime.now(timezone.utc).isoformat()} {msg}\n")


def transcript(obj: dict) -> None:
    with open(transcript_path, "a") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def now_ms() -> int:
    return int(time.time() * 1000)


# ---------------------------------------------------------------- harness cmd
if HARNESS == "occ":
    # Isolated Claude Code state per task-run (the wrapper respects the env).
    claude_home = run_dir / "claude-home"
    claude_home.mkdir()
    env["CLAUDE_CONFIG_DIR"] = str(claude_home)
    cmd = ["occ", "--model", MODEL_HANDLE, "-p", prompt,
           "--output-format", "stream-json", "--verbose"]
    try:
        cli_version = subprocess.run(["claude", "--version"], capture_output=True,
                                     text=True, timeout=30).stdout.strip()
    except Exception:
        cli_version = ""
else:
    # Isolated Codex home with the installer-managed provider config.
    codex_home = run_dir / "codex-home"
    codex_home.mkdir()
    managed = Path.home() / ".pi" / "agent-ocdx" / "codex"
    for name in ("config.toml", "models.json"):
        src = managed / name
        if src.exists():
            shutil.copy2(str(src), str(codex_home / name))
    env["CODEX_HOME"] = str(codex_home)
    cmd = ["ocdx", "--model", MODEL_HANDLE, "exec", "--skip-git-repo-check",
           "--json", prompt]
    try:
        cli_version = subprocess.run(["codex", "--version"], capture_output=True,
                                     text=True, timeout=30).stdout.strip()
    except Exception:
        cli_version = ""

# ---------------------------------------------------------------- run + parse
TOOL_MAP_OCC = {"Bash": "bash", "Read": "read", "Edit": "edit", "Write": "write"}

state = {
    "assistantTurns": 0,
    "apiTurns": 0,
    "toolCounts": {},
    "lastAssistantText": "",
    "nativeTools": None,
    "exitReason": "budget",
    "promptError": None,
    "usage": None,
    "finalResultText": None,
}
timed_out = threading.Event()


def count_tool(name: str) -> None:
    state["toolCounts"][name] = state["toolCounts"].get(name, 0) + 1


def flatten_content(c) -> str:
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for b in c:
            if isinstance(b, dict):
                parts.append(str(b.get("text") or b.get("content") or ""))
        return "\n".join(p for p in parts if p)
    return "" if c is None else str(c)


def handle_occ_event(e: dict) -> None:
    t = e.get("type")
    if t == "system" and e.get("subtype") == "init":
        state["nativeTools"] = e.get("tools")
    elif t == "assistant":
        state["assistantTurns"] += 1
        texts = []
        for b in ((e.get("message") or {}).get("content") or []):
            if not isinstance(b, dict):
                continue
            bt = b.get("type")
            if bt == "text" and b.get("text"):
                texts.append(str(b["text"]))
            elif bt == "tool_use":
                name = TOOL_MAP_OCC.get(str(b.get("name") or ""), str(b.get("name") or ""))
                cid = str(b.get("id") or "")
                id_to_name[cid] = name
                count_tool(name)
                transcript({"ts": now_ms(), "type": "tool_start", "toolName": name,
                            "toolCallId": cid, "args": b.get("input") or {}})
        text = "\n".join(texts).strip()
        if text:
            state["lastAssistantText"] = text
        transcript({"ts": now_ms(), "type": "turn_end", "text": text[:8000], "toolResults": []})
    elif t == "user":
        content = ((e.get("message") or {}).get("content"))
        for b in content if isinstance(content, list) else []:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                cid = str(b.get("tool_use_id") or "")
                transcript({"ts": now_ms(), "type": "tool_end",
                            "toolName": id_to_name.get(cid, "tool"), "toolCallId": cid,
                            "isError": bool(b.get("is_error")),
                            "text": flatten_content(b.get("content"))[:8000]})
    elif t == "result":
        state["apiTurns"] = e.get("num_turns") or state["apiTurns"]
        state["usage"] = e.get("usage") or state["usage"]
        if e.get("result"):
            state["finalResultText"] = str(e["result"])
        if e.get("subtype") not in ("success", None):
            state["promptError"] = str(e.get("subtype"))


def ocdx_item_name(it: dict):
    """Map a codex exec item to a normalized transcript tool name (or None)."""
    ty = it.get("type")
    if ty == "command_execution":
        return "bash"
    if ty == "file_change":
        return "edit"
    if ty == "mcp_tool_call":
        inv = it.get("invocation") if isinstance(it.get("invocation"), dict) else it
        return str(inv.get("tool") or inv.get("server") or "mcp_tool_call")
    return None


def handle_ocdx_event(e: dict) -> None:
    t = e.get("type")
    if t == "item.started":
        it = e.get("item") or {}
        name = ocdx_item_name(it)
        if name:
            iid = str(it.get("id") or "")
            id_to_name[iid] = name
            count_tool(name)
            args = {"command": it.get("command")} if it.get("command") is not None else {}
            transcript({"ts": now_ms(), "type": "tool_start", "toolName": name,
                        "toolCallId": iid, "args": args})
    elif t == "item.completed":
        it = e.get("item") or {}
        ty = it.get("type")
        iid = str(it.get("id") or "")
        if ty in ("command_execution", "file_change", "mcp_tool_call"):
            name = id_to_name.get(iid) or ocdx_item_name(it) or "tool"
            if ty == "command_execution":
                text = str(it.get("aggregated_output") or "")
                code = it.get("exit_code")
                is_err = code not in (0, None)
            elif ty == "file_change":
                text = json.dumps(it.get("changes") or [])[:8000]
                is_err = False
            else:
                text = json.dumps({k: v for k, v in it.items() if k not in ("id", "type")})[:8000]
                is_err = bool(it.get("isError") or it.get("is_error"))
            transcript({"ts": now_ms(), "type": "tool_end", "toolName": name,
                        "toolCallId": iid, "isError": is_err, "text": text[:8000]})
        elif ty == "agent_message":
            state["assistantTurns"] += 1
            text = str(it.get("text") or "").strip()
            if text:
                state["lastAssistantText"] = text
            transcript({"ts": now_ms(), "type": "turn_end", "text": text[:8000], "toolResults": []})
        elif ty == "error":
            state["promptError"] = str(it.get("text") or it.get("message") or "error item")
    elif t == "turn.completed":
        state["apiTurns"] += 1
        if e.get("usage"):
            state["usage"] = e["usage"]


id_to_name: dict = {}
handle_event = handle_occ_event if HARNESS == "occ" else handle_ocdx_event

started_at = datetime.now(timezone.utc).isoformat()
t0 = time.time()
log(f"task={TASK} harness={HARNESS} model={MODEL_LABEL} seed={SEED} "
    f"budget={BUDGET_S}s workdir={work_dir}")

proc = subprocess.Popen(
    cmd, cwd=str(work_dir), env=env, stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    start_new_session=True,
)
# NOTE: stdout stays BINARY on purpose: iterating a text-mode pipe applies
# universal-newline splitting, where a raw CR inside a JSON string would
# break JSONL framing. Binary iteration splits on LF only.


def watchdog() -> None:
    deadline = t0 + BUDGET_S
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(1)
    timed_out.set()
    log(f"budget {BUDGET_S}s reached; killing process group")
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        time.sleep(5)
        if proc.poll() is None:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except Exception as e:
        log(f"kill error: {e}")


threading.Thread(target=watchdog, daemon=True).start()

parse_errors = 0
with open(stream_path, "wb") as raw, open(run_dir / "stderr.log", "wb") as errf:
    # drain stderr in a thread so a chatty CLI can't wedge the pipe
    def drain_err():
        try:
            for chunk in proc.stderr:
                errf.write(chunk)
                errf.flush()
        except Exception:
            pass
    threading.Thread(target=drain_err, daemon=True).start()
    for raw_line in proc.stdout:
        raw.write(raw_line)
        raw.flush()
        line = raw_line.decode("utf-8", "replace").strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            parse_errors += 1
            continue
        try:
            handle_event(e)
        except Exception as ex:
            log(f"event handling error: {ex} on {line[:200]}")

rc = proc.wait()
# Agent wall time stops here: the 25 s grace and cleanup below must not
# inflate duration_s in the scorer.
cli_end = time.time()
cli_seconds = round(cli_end - t0, 1)
log(f"cli exited rc={rc} after {cli_seconds}s (timed_out={timed_out.is_set()}, "
    f"parse_errors={parse_errors})")

if timed_out.is_set():
    state["exitReason"] = "budget"
elif rc == 0:
    state["exitReason"] = "settled"
else:
    state["exitReason"] = f"cli_rc_{rc}"

# ------------------------------------------------- grace, then kill leftovers
grace = min(GRACE_S, max(0.0, BUDGET_S - (time.time() - t0)))
if grace > 0:
    log(f"grace window {grace:.0f}s for detached fixture jobs")
    time.sleep(grace)


def kill_pid_files(d: Path) -> None:
    for p in d.rglob("*.pid"):
        try:
            pid = int(p.read_text().strip())
            if pid > 0:
                os.kill(pid, signal.SIGTERM)
                log(f"killed leftover pid {pid} ({p})")
        except Exception:
            pass


kill_pid_files(work_dir)

ended_at = datetime.now(timezone.utc).isoformat()
final_text = state["finalResultText"] or state["lastAssistantText"]
run = {
    "task": TASK,
    "model": MODEL_LABEL,
    "harness": HARNESS,
    "cliVersion": cli_version,
    "seed": SEED,
    "nonce": nonce,
    "mbPort": mb_port,
    "budgetSeconds": BUDGET_S,
    "startedAt": started_at,
    "endedAt": ended_at,
    "durationMs": int((cli_end - t0) * 1000),
    "exitReason": state["exitReason"],
    "promptError": state["promptError"],
    "watcherStarts": 0,        # the monitor extension does not exist here
    "monitorEventPings": 0,
    "assistantTurns": state["assistantTurns"],
    "apiTurns": state["apiTurns"],
    "toolCounts": state["toolCounts"],
    "nativeTools": state["nativeTools"],
    "usage": state["usage"],
    "fixtureHashes": fixture_hashes,
    "finalText": final_text[:4000],
}
(run_dir / "run.json").write_text(json.dumps(run, indent=2))
log(f"done: exitReason={run['exitReason']} durationMs={run['durationMs']} "
    f"toolCounts={run['toolCounts']}")
print(f"[{HARNESS}:{TASK}] finished ({run['exitReason']}) in "
      f"{round(run['durationMs'] / 1000)}s tools={run['toolCounts']}")
