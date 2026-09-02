#!/usr/bin/env python3
"""Difficulty gate (TODO.md section 4).

Checks:
  - every task has a complete rubric; bucket matches task.toml difficulty
  - a hard task must derive difficulty from reasoning/debugging/adversarial
    depth or dependent stages, not from prompt length or timeouts alone
  - suite contains easy, medium, and hard tasks
  - every competency has a covering task at or above its required difficulty
    floor, unless the covering task documents an intentional probe waiver
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

    # competency difficulty floors
    inv = json.loads((ROOT / 'specs/tb21_competencies.json').read_text())
    cov = json.loads((ROOT / 'specs/coverage.json').read_text())
    matrix = cov['matrix']
    # documented environmentally-infeasible competencies are waived
    infeasible_ids = set()
    infeas_dir = ROOT / 'private-audit/infeasible'
    if infeas_dir.exists():
        import glob as _glob
        for f in _glob.glob(str(infeas_dir / '*.json')):
            try:
                infeasible_ids |= set(json.loads(Path(f).read_text())
                                      .get('competencies', []))
            except Exception:
                pass
    for c in inv['competencies']:
        cid = c['id']
        if cid in infeasible_ids:
            continue
        floor = c.get('min_required_difficulty', 'easy')
        cells = matrix.get(cid, [])
        ok = False
        for cell in cells:
            t = tasks.get(cell['task_id'])
            if not t:
                continue
            if DIFF_ORDER.get(t['bucket'], 0) >= DIFF_ORDER[floor]:
                ok = True
                break
            if t.get('documented_probe'):
                ok = True  # intentional, documented probe
                break
        if not ok and cells:
            problems.append(f'{cid}: no covering task at difficulty >= {floor} '
                            'and no documented probe waiver')
        elif not cells:
            problems.append(f'{cid}: uncovered (see check_tb21_coverage)')

    print(f'tasks={len(tasks)} buckets={counts} problems={len(problems)}')
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
