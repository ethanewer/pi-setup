#!/usr/bin/env python3
"""Build oracle-verification task batches for the harbor runs.

Splits tasks into N batch directories (via symlinks? no — harbor needs real
dirs; instead we emit N task-name list files and run harbor with a filtered
dataset path per batch using a temp dir of symlinks).
"""
import json, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "tasks"

def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    lint = json.loads((ROOT / "specs/lint_report.json").read_text())
    good = sorted(d.name for d in TASKS.iterdir()
                  if d.is_dir() and d.name in set(lint.get("ok_names", [])) or True)
    # recompute ok set from report
    bad = set(lint["bad"])
    names = sorted(d.name for d in TASKS.iterdir() if d.is_dir() and d.name not in bad)
    outdir = ROOT / "specs/oracle_batches"
    outdir.mkdir(exist_ok=True)
    for old in outdir.glob("batch-*.txt"):
        old.unlink()
    per = (len(names) + n - 1) // n
    for i in range(n):
        chunk = names[i * per:(i + 1) * per]
        (outdir / f"batch-{i:02d}.txt").write_text("\n".join(chunk) + "\n")
    print(f"{len(names)} tasks -> {n} batches of ~{per}")

if __name__ == "__main__":
    main()
