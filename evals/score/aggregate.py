#!/usr/bin/env python3
"""Aggregate scores across the per-model dirs of a run-multi base dir.

Usage: python3 score/aggregate.py results/<base>
Prints per-model adoption/trust/outcome rates across all seeds.
"""
import json
import os
import sys
from collections import defaultdict

LONG_TASKS = ["t1", "t2", "t3", "t4"]


def main():
    base = os.path.abspath(sys.argv[1])
    models = defaultdict(list)  # model -> list of per-task rows (all seeds)
    for d in sorted(os.listdir(base)):
        sj = os.path.join(base, d, "scores.json")
        if not os.path.isdir(os.path.join(base, d)) or not os.path.exists(sj):
            continue
        data = json.load(open(sj))
        model = data["meta"]["model"]
        models[model].extend(data["tasks"])

    hdr = (f"{'model':45} {'seeds':5} {'adopt':6} {'trust':6} {'adopt+':6} "
           f"{'avgblk':6} {'wake':4} {'outcm':6}")
    print(hdr)
    print("-" * len(hdr))
    for model, rows in sorted(models.items()):
        long_rows = [r for r in rows if r["task"] in LONG_TASKS]
        ctrl_rows = [r for r in rows if r["task"] not in LONG_TASKS]
        n = len(long_rows)
        seeds = len({r["seed"] for r in rows})
        adopted = [r for r in long_rows if r["used_monitor"]]
        trusted = [r for r in long_rows if r["used_monitor"] and r["bash_blocking_seconds"] == 0]
        # adoption without the tool is only "good" on control tasks
        avg_block = sum(r["bash_blocking_seconds"] for r in long_rows) / max(n, 1)
        wakeups = sum(r["spontaneous_wakeups"] for r in long_rows)
        ctrl_fp = sum(1 for r in ctrl_rows if r["used_monitor"])
        outcomes = [r["outcome_score"] for r in rows if r["outcome_score"] is not None]
        outcome = sum(outcomes) / len(outcomes) if outcomes else 0
        print(f"{model:45} {seeds:<5} "
              f"{len(adopted)}/{n:<4} {len(trusted)}/{n:<4} "
              f"{f'{len(adopted)}/{n} -fp{ctrl_fp}':<6} "
              f"{avg_block:<6.0f} {wakeups:<4} {outcome:<6.3f}")
        # per-task detail
        by_task = defaultdict(list)
        for r in long_rows:
            by_task[r["task"]].append(r)
        for t in sorted(by_task):
            rs = by_task[t]
            detail = " ".join(
                f"{'M' if r['used_monitor'] else '-'}{'T' if r['used_monitor'] and r['bash_blocking_seconds'] == 0 else '.'}"
                f"{int(r['bash_blocking_seconds'])}s"
                for r in sorted(rs, key=lambda x: x["seed"])
            )
            print(f"    {t}: {detail}")


if __name__ == "__main__":
    main()
