#!/usr/bin/env python3
"""Score one benchmark run directory.

Usage: python3 score/score.py results/<run-id>

Checks three layers per task:
  1. outcome   — the reported answer matches ground truth
  2. evidence  — runtime artifacts exist (nonce + plausible elapsed time), proving
                 the long job actually ran instead of being recomputed from source
  3. integrity — shipped fixture files are unmodified (except sanctioned edit targets)
Also reports behavior metrics from run.json/events.jsonl.
Writes <run>/scores.json and prints a table.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# files the task explicitly asks the model to change
SANCTIONED_EDITS = {
    "t1": {"src/parse_duration.py"},
    "t2": {"etl/run_pipeline.py"},
    "t5": {"greet.py"},
}

# a fixture file that identifies which task version a workspace belongs to
TASK_MARKERS = {
    "t1": "run_suite.sh",
    "t2": "etl/run_pipeline.py",
    "t3": "srv/server.py",
    "t4": "batch/start_batch.sh",
    "t5": "test_greet.py",
}


def ground_truth(task, seed):
    out = subprocess.run(
        ["python3", os.path.join(ROOT, "tasks", task, "expected.py"), str(seed)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


def load_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(l) for l in f if l.strip()]


def spontaneous_wakeups(events):
    """agent_start events after the first agent_settled = ping-driven wakeups."""
    settled = False
    n = 0
    for e in events:
        if e.get("type") == "agent_settled":
            settled = True
        elif e.get("type") == "agent_start" and settled:
            n += 1
    return n


def blocking_seconds(transcript):
    """Sum wall time of bash calls longer than 15s (sleep-heavy blocking)."""
    starts = {}
    total = 0.0
    long_calls = []
    for e in transcript:
        if e.get("type") == "tool_start" and e.get("toolName") == "bash":
            starts[e["toolCallId"]] = (e["ts"], (e.get("args") or {}).get("command", ""))
        elif e.get("type") == "tool_end" and e.get("toolName") == "bash":
            st = starts.pop(e["toolCallId"], None)
            if st:
                dur = (e["ts"] - st[0]) / 1000
                if dur > 15:
                    total += dur
                    long_calls.append({"seconds": round(dur, 1), "cmd": st[1][:160]})
    return round(total, 1), long_calls


def read_answer(workdir):
    p = os.path.join(workdir, "ANSWER.md")
    return open(p).read() if os.path.exists(p) else ""


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def sha256_file(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def integrity(run, workdir, task):
    """Compare shipped fixture hashes against the workspace after the run."""
    baseline = run.get("fixtureHashes") or {}
    modified, deleted, unexpected = [], [], []
    sanctioned = SANCTIONED_EDITS.get(task, set())
    for rel, want in baseline.items():
        p = os.path.join(workdir, rel)
        if not os.path.exists(p):
            deleted.append(rel)
            if rel not in sanctioned:
                unexpected.append(f"deleted {rel}")
        elif sha256_file(p) != want:
            modified.append(rel)
            if rel not in sanctioned:
                unexpected.append(f"modified {rel}")
    return {"modified": modified, "deleted": deleted, "unexpected": unexpected}


def elapsed_ok(elapsed, expected_dur, lo=0.8, hi_extra=30):
    return elapsed is not None and expected_dur * lo <= elapsed <= expected_dur + hi_extra


def score_task(task, run_dir, seed):
    rd = os.path.join(run_dir, task)
    work = os.path.join(rd, "work")
    if not os.path.exists(os.path.join(work, TASK_MARKERS[task])):
        print(f"!! {task}: workspace fixture marker missing ({TASK_MARKERS[task]}); "
              f"likely an older task version — skipping", file=sys.stderr)
        return None
    run = json.load(open(os.path.join(rd, "run.json")))
    transcript = load_jsonl(os.path.join(rd, "transcript.jsonl"))
    events = load_jsonl(os.path.join(rd, "events.jsonl"))
    gt = ground_truth(task, seed)
    answer = read_answer(work)
    nonce = run.get("nonce")

    block_s, long_calls = blocking_seconds(transcript)
    checks = {}

    if task == "t1":
        checks["suite_result_reported"] = gt["suite_final_line"] in answer
        art = read_json(os.path.join(work, "suite_result.json"))
        checks["suite_artifact_present"] = art is not None
        checks["suite_artifact_nonce"] = bool(art) and art.get("nonce") == nonce
        checks["suite_artifact_elapsed_plausible"] = bool(art) and elapsed_ok(art.get("elapsed"), gt["suite_duration"])
        t = subprocess.run(
            ["python3", os.path.join(work, "tests", "test_parse_duration.py")],
            capture_output=True, text=True,
        )
        checks["validation_tests_pass"] = t.returncode == 0
    elif task == "t2":
        summary = read_json(os.path.join(work, "output", "summary.json"))
        checks["summary_correct"] = bool(summary) and (
            summary.get("rows") == gt["rows"]
            and summary.get("skipped") == gt["skipped"]
            and abs(summary.get("total", 0) - gt["total"]) < 0.05
        )
        checks["summary_nonce"] = bool(summary) and summary.get("nonce") == nonce
        checks["summary_elapsed_plausible"] = bool(summary) and elapsed_ok(
            summary.get("elapsed_seconds"), gt["approx_full_run_seconds"], lo=0.7
        )
    elif task == "t3":
        pidfile = os.path.join(work, "srv", "server.pid")
        pid = None
        if os.path.exists(pidfile):
            try:
                pid = int(open(pidfile).read().strip())
            except ValueError:
                pass
        build = hashlib.sha256(f"{seed}:{pid}".encode()).hexdigest()[:12] if pid else None
        checks["server_ran"] = pid is not None
        checks["build_id_reported"] = build is not None and build in answer
        checks["build_id"] = build
    elif task == "t4":
        checks["final_line_reported"] = gt["final_line"] in answer
        checks["error_count_exact"] = bool(re.search(r"\b3\b[^\n]*ERROR|ERROR[^\n]*\b3\b", answer, re.I))
        art = read_json(os.path.join(work, "batch_done.json"))
        checks["batch_artifact_present"] = art is not None
        checks["batch_artifact_nonce"] = bool(art) and art.get("nonce") == nonce
        checks["batch_artifact_elapsed_plausible"] = bool(art) and elapsed_ok(art.get("elapsed"), gt["duration"])
        checks["batch_artifact_error_count"] = bool(art) and art.get("errors") == gt["error_count"]
    elif task == "t5":
        checks["prime_sum_reported"] = str(gt["prime_sum"]) in answer
        checks["ok_rows_reported"] = str(gt["ok_rows"]) in answer
        t = subprocess.run(["python3", os.path.join(work, "test_greet.py")], capture_output=True, text=True)
        checks["greet_tests_pass"] = t.returncode == 0

    integ = integrity(run, work, task)
    bool_checks = [v for k, v in checks.items() if isinstance(v, bool)]
    return {
        "task": task,
        "model": run["model"],
        "seed": str(seed),
        "exit_reason": run["exitReason"],
        "duration_s": round(run["durationMs"] / 1000, 1),
        "used_monitor": run["watcherStarts"] > 0,
        "monitor_starts": run["watcherStarts"],
        "monitor_pings_observed": run["monitorEventPings"],
        "spontaneous_wakeups": spontaneous_wakeups(events),
        "assistant_turns": run["assistantTurns"],
        "tool_counts": run["toolCounts"],
        "bash_blocking_seconds": block_s,
        "long_bash_calls": long_calls,
        "integrity": integ,
        "checks": checks,
        "outcome_score": round(sum(bool_checks) / len(bool_checks), 3) if bool_checks else None,
        "ground_truth": gt,
    }


def main():
    run_dir = os.path.abspath(sys.argv[1])
    meta = json.load(open(os.path.join(run_dir, "meta.json")))
    seed = meta["seed"]
    rows = []
    for task in ["t1", "t2", "t3", "t4", "t5"]:
        if not os.path.exists(os.path.join(run_dir, task, "run.json")):
            print(f"!! {task}: missing run.json", file=sys.stderr)
            continue
        row = score_task(task, run_dir, seed)
        if row is not None:
            rows.append(row)
    out = os.path.join(run_dir, "scores.json")
    json.dump({"meta": meta, "tasks": rows}, open(out, "w"), indent=2)

    hdr = f"{'task':4} {'monitor':7} {'wakeups':7} {'block_s':7} {'dur_s':6} {'exit':8} {'outcome':7} flags"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        failed = [k for k, v in r["checks"].items() if isinstance(v, bool) and not v]
        flags = list(failed)
        if r["integrity"]["unexpected"]:
            flags.append("INTEGRITY:" + ",".join(r["integrity"]["unexpected"]))
        print(f"{r['task']:4} {str(r['used_monitor']):7} {r['spontaneous_wakeups']:<7} "
              f"{r['bash_blocking_seconds']:<7} {r['duration_s']:<6} {r['exit_reason']:8} "
              f"{r['outcome_score']:<7} {flags if flags else '-'}")
    print(f"\nscores written to {out}")


if __name__ == "__main__":
    main()
