#!/usr/bin/env python3
"""Report the tasks no harness/model pair ever passed, classified by oracle sweep.

A task that nothing passes is either hard or broken, and the two call for opposite
responses: a hard task is the benchmark working, a broken one is a defect that has
been scoring every agent 0 and calling that a measurement. The only way to tell
them apart without reading 787 verifiers by hand is to run each task's own
reference solution and see whether it can pass.

So this joins two inputs:

  --tree    a published record tree (v3.4/<harness>/<provider>/<model>/<task>/),
            from which "never passed" is computed as a best reward of 0 across
            every pair that scored the task.
  --oracle  one or more harbor job directories produced by the oracle agent, whose
            per-task reward decides the classification.

A task whose oracle earns reward 1 is classified "hard": the task is solvable and
no agent managed it. A task whose oracle cannot earn reward 1 is "broken", and the
failure text from its verifier is carried into the report so the defect can be read
without re-running anything. Tasks with no oracle trial are reported as "unswept"
rather than guessed at.

Usage:
  python3 tools/report_never_passed.py --tree /tmp/hf-upload/v3.4 \
      --oracle /path/to/jobs/v34-oracle-all [--oracle /path/to/jobs/v34-verify-repairs] \
      --out /tmp/v34_never_passed.json
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path


def tree_rewards(tree: Path):
    """{(pair, task): reward} for every record under a published tree."""
    out = {}
    for rp in tree.rglob('verifier/reward.txt'):
        parts = rp.relative_to(tree).parts
        # <harness>/<provider>/<model>/<task>/verifier/reward.txt
        if len(parts) != 6:
            continue
        pair = '/'.join(parts[:3])
        task = parts[3]
        try:
            out[(pair, task)] = float(rp.read_text().strip())
        except (OSError, ValueError):
            continue
    return out


def oracle_results(jobs):
    """{task: (reward_string, last verifier lines)} across every oracle job.

    Later jobs win, so a re-verification after a repair overrides the census that
    found the defect.
    """
    res = {}
    for job in jobs:
        job = Path(job)
        if not job.is_dir():
            print('warning: oracle job dir missing: %s' % job, file=sys.stderr)
            continue
        for rj in sorted(job.glob('*__*/result.json')):
            td = rj.parent
            task = None
            try:
                task = json.loads(rj.read_text()).get('task_name')
            except (OSError, ValueError):
                pass
            if not task:
                task = td.name.split('__')[0]
            rw = td / 'verifier/reward.txt'
            val = rw.read_text().strip() if rw.is_file() else 'ABSENT'
            tail = []
            so = td / 'verifier' / 'test-stdout.txt'
            if so.is_file():
                lines = [l for l in so.read_text(errors='replace').splitlines() if l.strip()]
                tail = lines[-3:]
            exc = None
            try:
                e = json.loads(rj.read_text()).get('exception_info')
                exc = (e or {}).get('exception_type')
            except (OSError, ValueError):
                pass
            res[task] = (val, tail, exc)
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--tree', required=True, type=Path)
    ap.add_argument('--oracle', action='append', required=True)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--version', default=None)
    args = ap.parse_args()

    rewards = tree_rewards(args.tree)
    if not rewards:
        print('FATAL: no records found under %s' % args.tree, file=sys.stderr)
        return 2
    oracle = oracle_results(args.oracle)

    pairs = sorted({p for p, _ in rewards})
    tasks = sorted({t for _, t in rewards})

    never, rows = [], []
    for task in tasks:
        scored = {p: rewards[(p, task)] for p in pairs if (p, task) in rewards}
        if not scored:
            continue
        if max(scored.values()) > 0.0:
            continue
        o = oracle.get(task)
        if o is None:
            classification, detail = 'unswept', 'no oracle trial for this task'
        elif o[0] in ('1', '1.0'):
            classification = 'hard'
            detail = ('the task\'s own reference solution earns reward 1, so the '
                      'task is solvable and no pair managed it')
        else:
            classification = 'broken'
            bits = []
            if o[2]:
                bits.append('trial exception %s' % o[2])
            if o[0] == 'ABSENT':
                bits.append('no reward written')
            bits.extend(o[1])
            detail = '; '.join(bits) or 'oracle earned reward %s' % o[0]
        row = {'task': task,
               'best_reward_across_pairs': max(scored.values()),
               'pairs_scored': len(scored),
               'classification': classification,
               'oracle_reward': (o[0] if o else None),
               'detail': detail}
        rows.append(row)
        never.append(task)

    counts = Counter(r['classification'] for r in rows)
    version = args.version or args.tree.name
    payload = {
        'artifact': 'tasks no harness/model pair ever passed',
        'version': version,
        'note': ('Computed from the published record tree by joining every task '
                 'whose best reward across all scoring pairs is 0 against an '
                 'oracle sweep of the same suite. "hard" means the task\'s own '
                 'reference solution passes, so the task is solvable and nothing '
                 'solved it. "broken" means the reference solution cannot pass '
                 'either, so every pair was scored 0 by a defect rather than by '
                 'performance; the verifier\'s own last lines are carried in '
                 'detail so the defect can be read without re-running it.'),
        'pairs': pairs,
        'tasks_in_suite': len(tasks),
        'count': len(rows),
        'classification_counts': dict(sorted(counts.items())),
        'oracle_jobs': [str(Path(j)) for j in args.oracle],
        'tasks': rows,
    }
    args.out.write_text(json.dumps(payload, indent=1) + '\n')

    print('%s: %d of %d tasks never passed by any pair'
          % (version, len(rows), len(tasks)))
    for k, v in sorted(counts.items()):
        print('  %-9s %d' % (k, v))
    print('wrote %s' % args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
