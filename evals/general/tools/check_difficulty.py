#!/usr/bin/env python3
"""Difficulty gate (TODO.md section 4).

Checks:
  - every task has a complete rubric; bucket matches task.toml difficulty
  - a hard task must derive difficulty from reasoning/debugging/adversarial
    depth or dependent stages, not from prompt length or timeouts alone
  - suite contains easy, medium, and hard tasks
  - oracle times are recorded (waive mid-development with --allow-unmeasured)
"""
import argparse, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIFF_ORDER = {'easy': 0, 'medium': 1, 'hard': 2}
DEPTH_KEYS = ('reasoning_depth', 'debugging_ambiguity', 'adversarial_inputs',
              'dependent_stages')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--allow-unmeasured', action='store_true',
                    help='accept missing oracle timings (mid-development only)')
    args = ap.parse_args()

    problems = []
    diff = json.loads((ROOT / 'specs/difficulty.json').read_text())
    tasks = diff['tasks']
    counts = diff['suite_counts']

    for b in ('easy', 'medium', 'hard'):
        if counts.get(b, 0) < 1:
            problems.append(f'suite has no {b} tasks')

    for name, t in tasks.items():
        if t['bucket'] != t['task_toml_difficulty']:
            problems.append(f'{name}: rubric bucket {t["bucket"]} != '
                            f'task.toml difficulty {t["task_toml_difficulty"]}')
        if t['bucket'] == 'hard':
            rub = t['rubric']
            if max((rub.get(k) or 0) for k in DEPTH_KEYS) < 2:
                problems.append(f'{name}: declared hard but no depth dimension '
                                '>= 2 (difficulty must come from reasoning, '
                                'not prompt length or timeouts)')
        if t['oracle_time_sec'] is None and not args.allow_unmeasured:
            problems.append(f'{name}: oracle time not measured')
        if t['oracle_reward'] not in (None, 1, 1.0) and t['oracle_reward'] is not None:
            problems.append(f'{name}: oracle reward {t["oracle_reward"]} != 1')


    print(f'tasks={len(tasks)} buckets={counts} problems={len(problems)}')
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
