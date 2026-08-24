#!/usr/bin/env python3
"""Collect oracle2 results across all job dirs (o2-chunk-*, o2-re-chunk-*,
o2-fix-*) into a single per-task status report: specs/oracle2_report.json.

For each task in specs/all_tasks.txt, the latest completed trial wins
(fix > re-chunk > chunk).
"""
import json, glob, os, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JOBS = ROOT / "jobs-oracle2"
all_tasks = [l.strip() for l in open(ROOT / "specs/all_tasks.txt") if l.strip()]

def tier(jobname):
    if jobname.startswith("o2-fix-"): return 2
    if jobname.startswith("o2-re-chunk-"): return 1
    return 0

best = {}  # task -> (tier, reward, exc, jobdir)
for jobdir in sorted(JOBS.glob("o2-*")):
    if not jobdir.is_dir(): continue
    t = tier(jobdir.name)
    for trial in jobdir.glob("*__*"):
        rj = trial / "result.json"
        if not rj.exists(): continue
        try:
            r = json.loads(rj.read_text())
        except Exception:
            continue  # trial still in progress
        name = r.get("task_name") or trial.name.rsplit("__", 1)[0]
        # task names may be truncated in trial dir names; trust task_name
        rw = (r.get("verifier_result") or {}).get("rewards", {}).get("reward")
        exc = (r.get("exception_info") or {}).get("exception_type")
        cur = best.get(name)
        if cur is None or t >= cur[0]:
            best[name] = (t, rw, exc, jobdir.name)

passed, zero, partial, errored, missing = [], [], [], [], []
for t in all_tasks:
    if t not in best:
        missing.append(t); continue
    _, rw, exc, _ = best[t]
    if exc:
        errored.append(t)
    elif rw == 1 or rw == 1.0:
        passed.append(t)
    elif rw == 0 or rw == 0.0:
        zero.append(t)
    else:
        partial.append((t, rw))

out = {
    "passed": sorted(passed),
    "zero": sorted(zero),
    "partial": sorted(partial),
    "errored": sorted(errored),
    "missing": sorted(missing),
    "n": len(all_tasks),
    "n_green": len(passed),
}
(ROOT / "specs/oracle2_report.json").write_text(json.dumps(out, indent=1))
print(f"green {len(passed)}/{len(all_tasks)}  zero {len(zero)}  partial {len(partial)}  errored {len(errored)}  missing {len(missing)}")
if zero: print("ZERO:", zero)
if partial: print("PARTIAL:", partial)
if errored: print("ERRORED:", errored)
if missing: print("MISSING:", missing)
