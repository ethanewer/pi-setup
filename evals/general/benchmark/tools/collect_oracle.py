#!/usr/bin/env python3
"""Aggregate oracle results across all known oracle/repro job prefixes.

Keeps the LATEST result per task (by job mtime). Writes specs/oracle_report.json.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JOBS = ROOT / "jobs"
PATTERNS = ["oracle-full-*", "oracle-chunk-*", "oracle-re-*", "repro-*", "item075-re*", "oracle-fix-*"]

def main():
    latest = {}
    for pat in PATTERNS:
        for job in sorted(JOBS.glob(pat), key=lambda p: p.stat().st_mtime):
            for trial_dir in job.iterdir():
                if not trial_dir.is_dir():
                    continue
                tres = trial_dir / "result.json"
                if not tres.exists():
                    continue
                try:
                    t = json.loads(tres.read_text())
                except Exception:
                    continue
                name = t.get("task_name") or trial_dir.name.rsplit("__", 1)[0]
                exc = t.get("exception_info")
                rewards = t.get("verifier_result") or {}
                reward = (rewards.get("rewards") or {}).get("reward")
                latest[name] = (exc["exception_type"] if exc else None, reward)

    passed = sorted(n for n, (e, r) in latest.items() if e is None and r == 1)
    zero = sorted(n for n, (e, r) in latest.items() if e is None and r == 0)
    partial = sorted(n for n, (e, r) in latest.items() if e is None and r not in (0, 1, None))
    errored = sorted(n for n, (e, r) in latest.items() if e is not None)
    report = {"passed": passed, "zero": zero, "partial": partial, "errored": errored}
    (ROOT / "specs/oracle_report.json").write_text(json.dumps(report, indent=1))
    print(f"latest-per-task: pass={len(passed)} zero={len(zero)} partial={len(partial)} exc={len(errored)}")

if __name__ == "__main__":
    main()
