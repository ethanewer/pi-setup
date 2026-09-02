#!/usr/bin/env python3
"""Aggregate browser-bench scores across runs, grouped by arm x model.

Usage: python3 score/aggregate.py [label] <run-dir> [<run-dir> ...]
"""
import json
import sys
from pathlib import Path


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    label = "all"
    dirs = args
    while dirs and not Path(dirs[0]).is_dir():
        label = dirs.pop(0)
    rows = []
    for d in dirs:
        p = Path(d)
        for task_dir in sorted(p.iterdir()):
            sf = task_dir / "score.json"
            if task_dir.is_dir() and sf.exists():
                rows.append(json.loads(sf.read_text()))
    if not rows:
        print("nothing scored yet; run score/score.py first")
        sys.exit(1)

    groups = {}
    for r in rows:
        groups.setdefault((r["arm"], r["model"]), []).append(r)

    print(f"\n=== browser-bench: {label} ({len(rows)} runs) ===")
    header = (f"{'arm':26s} {'model':22s} {'n':>3s} {'out':>5s} {'calls':>6s} {'cli':>4s} {'dups':>5s} "
              f"{'chal':>5s} {'solv':>5s} {'loop':>4s} {'429':>4s} {'ignRA':>5s} {'ints':>5s} {'time':>6s} {'tokens':>7s}")
    print(header)
    for (arm, model) in sorted(groups):
        rs = groups[(arm, model)]
        n = len(rs)
        avg = lambda k: sum(x.get(k, 0) for x in rs) / n
        outcome = sum(x["outcome"] for x in rs) / n
        chal = sum(x["challenge_served"] for x in rs)
        solved = sum(x["challenge_solved"] for x in rs)
        loops = sum(1 for x in rs if x["challenge_loop"])
        mshort = model.split("/")[-1][:22]
        print(f"{arm:26s} {mshort:22s} {n:>3d} {outcome:>5.2f} {avg('browser_calls')+avg('browser_cli_calls'):>6.1f} "
              f"{avg('browser_cli_calls'):>4.1f} {avg('duplicate_calls'):>5.1f} {chal:>5d} {solved:>5d} {loops:>4d} "
              f"{sum(x['rate_limited'] for x in rs):>4d} {sum(x['ignored_retry_after'] for x in rs):>5d} "
              f"{sum(x['interstitials'] for x in rs):>5d} {avg('durationS'):>6.1f} {avg('tokens'):>7.0f}")
    print("\nper-task outcomes:")
    tasks = sorted({r["task"] for r in rows})
    print(f"{'arm':26s} {'model':22s} " + " ".join(f"{t:>6s}" for t in tasks))
    for (arm, model) in sorted(groups):
        rs = groups[(arm, model)]
        cells = []
        for t in tasks:
            ts = [x["outcome"] for x in rs if x["task"] == t]
            cells.append(f"{(sum(ts)/len(ts)) if ts else float('nan'):>6.2f}")
        print(f"{arm:26s} {model.split('/')[-1][:22]:22s} " + " ".join(cells))


if __name__ == "__main__":
    main()
