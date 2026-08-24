#!/usr/bin/env python3
"""Audit a benchmark job: classify per-task results, detect anomalies.

Outputs specs/audit_<job>.json with:
  - summary: counts, mean reward, token/cost stats
  - anomalies: tasks with exceptions, missing rewards, or mismatches
    where oracle passed but model scored 0 in trivial tasks (signal of
    benchmark/agent integration breakage).
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = json.loads((ROOT / "specs/plan.json").read_text())

def audit(job_name: str):
    job = ROOT / "jobs" / job_name
    trials = list(job.glob("*/result.json"))
    per_task = {}
    anomalies = []
    total_cost = 0.0
    n_input = n_output = 0
    for t in trials:
        d = json.loads(t.read_text())
        name = d.get("task_name") or t.parent.name.rsplit("__", 1)[0]
        vr = d.get("verifier_result") or {}
        rw = (vr.get("rewards") or {}).get("reward")
        exc = d.get("exception_info")
        ac = d.get("agent_context") or {}
        total_cost += ac.get("cost_usd") or 0.0
        n_input += ac.get("n_input_tokens") or 0
        n_output += ac.get("n_output_tokens") or 0
        per_task[name] = rw
        if exc:
            anomalies.append({"task": name, "kind": "exception",
                              "info": exc["exception_type"]})
        elif rw is None:
            anomalies.append({"task": name, "kind": "no_reward"})
    planned = {t["name"]: t for t in PLAN["item_tasks"] + PLAN["skill_tasks"]}
    missing = sorted(set(planned) - set(per_task))
    passed = [k for k, v in per_task.items() if v == 1]
    partial = {k: v for k, v in per_task.items() if v not in (None, 0, 1)}
    zero = [k for k, v in per_task.items() if v == 0]
    trivial_zero = [z for z in zero if planned.get(z, {}).get("difficulty") == "easy"]
    out = {
        "job": job_name,
        "n_trials": len(trials),
        "passed": len(passed),
        "zero": len(zero),
        "partial": len(partial),
        "missing": missing,
        "anomalies": anomalies,
        "trivial_zero_count": len(trivial_zero),
        "cost_usd": round(total_cost, 4),
        "n_input_tokens": n_input,
        "n_output_tokens": n_output,
        "mean_reward": round(sum(v for v in per_task.values() if v is not None) / max(len(per_task), 1), 4),
    }
    (ROOT / f"specs/audit_{job_name}.json").write_text(json.dumps(out, indent=1))
    print(json.dumps(out, indent=1)[:2500])

if __name__ == "__main__":
    audit(sys.argv[1])
