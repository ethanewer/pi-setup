#!/usr/bin/env python3
"""Summarize harbor job dirs: reward per task, pass rate, exceptions."""
import json, sys
from pathlib import Path

def summarize(job: Path):
    trials = [d for d in job.iterdir() if d.is_dir() and "__" in d.name]
    n = len(trials)
    reward = 0.0
    scored = 0
    exc_counts: dict[str, int] = {}
    no_reward = []
    for t in trials:
        task = t.name.rsplit("__", 1)[0]
        rfile = t / "verifier" / "reward.txt"
        try:
            reward += float(rfile.read_text().strip())
            scored += 1
        except (FileNotFoundError, ValueError):
            no_reward.append(task)
        rj = t / "result.json"
        if rj.exists():
            try:
                data = json.loads(rj.read_text())
                exc = (data.get("agent") or {}).get("exception") or data.get("exception")
                if exc:
                    exc_counts[type(exc).__name__ if not isinstance(exc, str) else exc] = \
                        exc_counts.get(type(exc).__name__ if not isinstance(exc, str) else exc, 0) + 1
            except Exception:
                pass
    print(f"{job.name}: trials={n} scored={scored} reward={reward:.0f} "
          f"pass_rate={reward / n if n else 0:.3f}")
    if exc_counts:
        print(f"  exceptions: {exc_counts}")
    if no_reward:
        print(f"  no-reward trials ({len(no_reward)}): {', '.join(sorted(no_reward)[:20])}"
              + (" ..." if len(no_reward) > 20 else ""))

if __name__ == "__main__":
    roots = [Path(p) for p in (sys.argv[1:] or ["/home/ee/general-eval-runs/jobs"])]
    for root in roots:
        jobs = sorted(d for d in root.iterdir() if d.is_dir() and (d / "result.json").exists()) \
            if root.is_dir() else []
        for j in jobs:
            summarize(j)
