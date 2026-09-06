#!/usr/bin/env python3
"""Rescore a published run tree under the binary reward contract.

45 task verifiers used to award partial credit. They now emit 0 or 1, and every
one of them was binarized at full credit: the new reward is 1 exactly where the
old reward was >= 1.0. That makes already-published records rescoring-able
without touching a model, because the old value determines the new one:

    old == 1.0 (or above)  ->  1
    old <  1.0             ->  0

Records with no verifier/reward.txt at all cannot be rescored. The published
tree kept only metadata.json, trajectory.json and the verifier's stdout, never
the agent's final filesystem, so reproducing a reward needs the trial re-run.

Usage:
  python3 tools/rescore_binary.py --tree DIR [--apply] [--json]

Without --apply this is a dry run that only reports. Exit code is 1 when any
record needs a re-run, so it can gate a publish.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

PAIR_DEPTH = 3
TASK_DEPTH = 4


def records_under(root: Path):
    for meta in sorted(root.rglob('metadata.json')):
        rel = meta.parent.relative_to(root).parts
        if len(rel) == TASK_DEPTH:
            yield '/'.join(rel[:PAIR_DEPTH]), rel[3], meta.parent


def rescore(tree: Path, apply: bool):
    per_pair = defaultdict(lambda: {'records': 0, 'already_binary': 0,
                                    'rescored': 0, 'needs_rerun': 0,
                                    'reward_before': 0.0, 'reward_after': 0.0,
                                    'rescored_tasks': set(),
                                    'rerun_tasks': set()})
    for pair, task, rec in records_under(tree):
        s = per_pair[pair]
        s['records'] += 1
        rp = rec / 'verifier/reward.txt'
        if not rp.is_file():
            s['needs_rerun'] += 1
            s['rerun_tasks'].add(task)
            continue
        raw = rp.read_text().strip()
        try:
            val = float(raw.splitlines()[-1]) if raw else None
        except ValueError:
            val = None
        if val is None:
            s['needs_rerun'] += 1
            s['rerun_tasks'].add(task)
            continue
        new = 1.0 if val >= 1.0 else 0.0
        s['reward_before'] += val
        s['reward_after'] += new
        if new == val:
            s['already_binary'] += 1
        else:
            s['rescored'] += 1
            s['rescored_tasks'].add(task)
            if apply:
                rp.write_text('%d\n' % int(new))
    return per_pair


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--tree', type=Path, required=True)
    ap.add_argument('--apply', action='store_true',
                    help='rewrite reward.txt files in place')
    ap.add_argument('--json', action='store_true')
    args = ap.parse_args()

    if not args.tree.is_dir():
        print(f'ERROR no such tree: {args.tree}')
        return 2

    per_pair = rescore(args.tree, args.apply)
    tot = defaultdict(int)
    tasks_rescored, tasks_rerun = set(), set()
    for s in per_pair.values():
        for k in ('records', 'already_binary', 'rescored', 'needs_rerun'):
            tot[k] += s[k]
        tot['reward_before'] += s['reward_before']
        tot['reward_after'] += s['reward_after']
        tasks_rescored |= s['rescored_tasks']
        tasks_rerun |= s['rerun_tasks']

    if args.json:
        print(json.dumps({
            'mode': 'apply' if args.apply else 'dry-run',
            'totals': {k: (round(v, 4) if isinstance(v, float) else v)
                       for k, v in tot.items()},
            'distinct_tasks_rescored': sorted(tasks_rescored),
            'distinct_tasks_needing_rerun': sorted(tasks_rerun),
            'pairs': {p: {k: (sorted(v) if isinstance(v, set) else
                              round(v, 4) if isinstance(v, float) else v)
                          for k, v in s.items()}
                      for p, s in sorted(per_pair.items())},
        }, indent=1))
    else:
        print(f"mode: {'APPLIED' if args.apply else 'dry run'}   tree: {args.tree}")
        print(f"{'pair':52s} {'recs':>5s} {'binary':>7s} {'rescored':>9s} "
              f"{'rerun':>6s} {'reward before':>14s} {'after':>9s}")
        for pair, s in sorted(per_pair.items()):
            print(f"{pair:52s} {s['records']:5d} {s['already_binary']:7d} "
                  f"{s['rescored']:9d} {s['needs_rerun']:6d} "
                  f"{s['reward_before']:14.2f} {s['reward_after']:9.2f}")
        print(f"\nrecords: {tot['records']}   already binary: {tot['already_binary']}")
        print(f"RESCORED (no inference needed): {tot['rescored']} records "
              f"across {len(tasks_rescored)} distinct tasks")
        print(f"NEEDS RE-RUN (no reward.txt):   {tot['needs_rerun']} records "
              f"across {len(tasks_rerun)} distinct tasks")
        print(f"total reward {tot['reward_before']:.2f} -> {tot['reward_after']:.2f}")
        if tasks_rerun:
            print('\ntasks needing a re-run:')
            for pair, s in sorted(per_pair.items()):
                if s['rerun_tasks']:
                    print(f"  {pair}: {sorted(s['rerun_tasks'])}")

    return 1 if tot['needs_rerun'] else 0


if __name__ == '__main__':
    sys.exit(main())
