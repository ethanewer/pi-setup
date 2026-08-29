#!/usr/bin/env python3
"""Aggregate browser-bench scores across runs, grouped by arm.

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
    # first arg that isn't a directory is the label
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

    arms = {}
    for r in rows:
        arms.setdefault(r["arm"], []).append(r)

    print(f"\n=== browser-bench: {label} ({len(rows)} runs) ===")
    header = (f"{'arm':26s} {'runs':>4s} {'outcome':>8s} {'browser':>7s} {'bash':>5s} {'dups':>5s} "
              f"{'chal':>5s} {'solved':>6s} {'loops':>5s} {'429':>4s} {'ignRA':>5s} {'ints':>5s} {'time':>7s} {'tokens':>8s}")
    print(header)
    for arm in sorted(arms):
        rs = arms[arm]
        n = len(rs)
        avg = lambda k: sum(x.get(k, 0) for x in rs) / n
        outcome = sum(x["outcome"] for x in rs) / n
        solved = sum(x["challenge_solved"] for x in rs)
        chal = sum(x["challenge_served"] for x in rs)
        loops = sum(1 for x in rs if x["challenge_loop"])
        print(f"{arm:26s} {n:>4d} {outcome:>8.2f} {avg('browser_calls'):>7.1f} {avg('bash_calls'):>5.1f} "
              f"{avg('duplicate_calls'):>5.1f} {chal:>5d} {solved:>6d} {loops:>5d} {sum(x['rate_limited'] for x in rs):>4d} "
              f"{sum(x['ignored_retry_after'] for x in rs):>5d} {sum(x['interstitials'] for x in rs):>5d} "
              f"{avg('durationS'):>7.1f} {avg('tokens'):>8.0f}")
    print("\nper-task outcomes:")
    tasks = sorted({r["task"] for r in rows})
    print(f"{'arm':26s} " + " ".join(f"{t:>6s}" for t in tasks))
    for arm in sorted(arms):
        rs = arms[arm]
        cells = []
        for t in tasks:
            ts = [x["outcome"] for x in rs if x["task"] == t]
            cells.append(f"{(sum(ts)/len(ts)) if ts else float('nan'):>6.2f}")
        print(f"{arm:26s} " + " ".join(cells))


if __name__ == "__main__":
    main()
