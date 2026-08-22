#!/usr/bin/env python3
"""Score one benchmark run directory.

Usage: python3 score/score.py results/<run-id>
Reads run.json/transcript.jsonl/ANSWER.md per task, compares against
tasks/<tN>/expected.py SEED, and writes <run>/scores.json + prints a table.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


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


def score_task(task, run_dir, seed):
    rd = os.path.join(run_dir, task)
    work = os.path.join(rd, "work")
    run = json.load(open(os.path.join(rd, "run.json")))
    transcript = load_jsonl(os.path.join(rd, "transcript.jsonl"))
    events = load_jsonl(os.path.join(rd, "events.jsonl"))
    gt = ground_truth(task, seed)
    answer = read_answer(work)

    block_s, long_calls = blocking_seconds(transcript)
    checks = {}

    if task == "t1":
        checks["suite_result_reported"] = gt["suite_final_line"] in answer
        t = subprocess.run(
            ["python3", os.path.join(work, "tests", "test_parse_duration.py")],
            capture_output=True, text=True,
        )
        checks["validation_tests_pass"] = t.returncode == 0
    elif task == "t2":
        sp = os.path.join(work, "output", "summary.json")
        ok = False
        summary = None
        if os.path.exists(sp):
            summary = json.load(open(sp))
            ok = (summary.get("rows") == gt["rows"]
                  and summary.get("skipped") == gt["skipped"]
                  and abs(summary.get("total", 0) - gt["total"]) < 0.05)
        checks["summary_correct"] = ok
        checks["summary_contents"] = summary
    elif task == "t3":
        checks["build_id_reported"] = gt["build"] in answer
    elif task == "t4":
        checks["final_line_reported"] = gt["final_line"] in answer
        checks["error_count_reported"] = bool(re.search(r"3", answer)) and "error" in answer.lower()
        # strict: exact count mentioned near the word error
        checks["error_count_exact"] = bool(re.search(r"\b3\b[^\n]*ERROR|ERROR[^\n]*\b3\b", answer, re.I))
    elif task == "t5":
        checks["a_checksum_reported"] = gt["a_checksum"] in answer
        checks["b_checksum_reported"] = gt["b_checksum"] in answer
    elif task == "t6":
        checks["prime_sum_reported"] = str(gt["prime_sum"]) in answer
        checks["ok_rows_reported"] = str(gt["ok_rows"]) in answer
        t = subprocess.run(["python3", os.path.join(work, "test_greet.py")], capture_output=True, text=True)
        checks["greet_tests_pass"] = t.returncode == 0

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
        "watchers_left_active": max(0, run["watcherStarts"] - run["watcherStops"]) if not run["watcherStops"] >= run["watcherStarts"] else 0,
        "assistant_turns": run["assistantTurns"],
        "tool_counts": run["toolCounts"],
        "bash_blocking_seconds": block_s,
        "long_bash_calls": long_calls,
        "checks": checks,
        "outcome_score": round(sum(bool_checks) / len(bool_checks), 3) if bool_checks else None,
        "ground_truth": gt,
    }


def main():
    run_dir = os.path.abspath(sys.argv[1])
    meta = json.load(open(os.path.join(run_dir, "meta.json")))
    seed = meta["seed"]
    rows = []
    for task in ["t1", "t2", "t3", "t4", "t5", "t6"]:
        if not os.path.exists(os.path.join(run_dir, task, "run.json")):
            print(f"!! {task}: missing run.json", file=sys.stderr)
            continue
        rows.append(score_task(task, run_dir, seed))
    out = os.path.join(run_dir, "scores.json")
    json.dump({"meta": meta, "tasks": rows}, open(out, "w"), indent=2)

    # table
    hdr = f"{'task':4} {'monitor':7} {'wakeups':7} {'block_s':7} {'dur_s':6} {'exit':8} {'outcome':7} checks"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        failed = [k for k, v in r["checks"].items() if isinstance(v, bool) and not v]
        print(f"{r['task']:4} {str(r['used_monitor']):7} {r['spontaneous_wakeups']:<7} "
              f"{r['bash_blocking_seconds']:<7} {r['duration_s']:<6} {r['exit_reason']:8} "
              f"{r['outcome_score']:<7} failed={failed if failed else '-'}")
    print(f"\nscores written to {out}")


if __name__ == "__main__":
    main()
