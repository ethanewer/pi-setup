#!/usr/bin/env python3
"""Terminal-Bench competency coverage gate (TODO.md section 2.4).

Failures:
  - missing reference competency (inventory id with no covering task)
  - competency mapped only to tasks that do not exercise it
  - missing verifier evidence
  - missing hard / second-task coverage where required
  - duplicate task or probe IDs
  - task absent from the matrix
  - skill listed in task metadata tags but not used by the task contract
Prints counts plus the complete list of uncovered competencies; exits nonzero
on any missing required competency.
"""
import json, re, sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

ROOT = Path(__file__).resolve().parents[1]
DIFF_ORDER = {'easy': 0, 'medium': 1, 'hard': 2}


def read_toml(p: Path) -> dict:
    if tomllib:
        return tomllib.loads(p.read_text())
    data, section = {}, None
    for line in p.read_text().splitlines():
        s = line.strip()
        if s.startswith('['):
            section = s.strip('[]')
            data.setdefault(section, {})
        elif '=' in s and section:
            k, _, v = s.partition('=')
            data[section][k.strip()] = v.strip().strip('"')
    return data


def slug(s: str) -> str:
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')


def main() -> int:
    problems = []
    inv = json.loads((ROOT / 'specs/tb21_competencies.json').read_text())
    cov_path = ROOT / 'specs/coverage.json'
    if not cov_path.exists():
        print('ERROR specs/coverage.json missing (run tools/build_coverage.py)')
        return 1
    cov = json.loads(cov_path.read_text())
    comps = {c['id']: c for c in inv['competencies']}
    matrix = cov['matrix']

    task_dirs = sorted(p.name for p in (ROOT / 'tasks').iterdir() if p.is_dir())
    if len(task_dirs) != len(set(task_dirs)):
        problems.append('duplicate task directory IDs')

    # every inventory competency must be covered
    uncovered = [cid for cid in comps if cid not in matrix or not matrix[cid]]
    for cid in uncovered:
        problems.append(f'missing reference competency: {cid} '
                        f'({comps[cid]["definition"][:70]})')

    weak = []
    for cid, cells in matrix.items():
        if cid not in comps:
            problems.append(f'unknown competency id in matrix: {cid}')
            continue
        spec = comps[cid]
        real = []
        for cell in cells:
            task = cell['task_id']
            if not (ROOT / 'tasks' / task).is_dir():
                problems.append(f'{cid}: covering task {task} does not exist')
                continue
            if not cell.get('evidence', '').strip():
                problems.append(f'missing verifier evidence: {cid} in {task}')
                continue
            vkind = cell.get('verifier_kind', '')
            if vkind not in ('executes-deliverable', 'answer-with-hidden-cases'):
                problems.append(f'{task}: unknown verifier_kind {vkind!r}')
                continue
            if not cell.get('hidden_cases'):
                problems.append(f'{cid}: {task} has no hidden cases or exemption')
                continue
            if vkind == 'answer-with-hidden-cases' and spec['risk'] == 'high':
                # answer-only verification cannot prove high-risk competencies
                weak.append((cid, task))
                continue
            real.append(cell)
        if not real:
            problems.append(f'competency mapped only to tasks that do not '
                            f'exercise it: {cid}')
            continue
        # second-task requirement for rare / high-risk competencies
        if spec.get('second_task_required') and len({c['task_id'] for c in real}) < 2:
            problems.append(f'{cid}: high-risk/rare competency needs two '
                            f'independent tasks, has {len(set(c["task_id"] for c in real))}')
        # difficulty floor
        floor = spec.get('min_required_difficulty', 'easy')
        if not any(DIFF_ORDER.get(c['difficulty'], 0) >= DIFF_ORDER[floor]
                   for c in real):
            problems.append(f'{cid}: no covering task at difficulty >= {floor}')

    for cid, task in weak:
        problems.append(f'{cid}: high-risk competency covered only by '
                        f'answer-comparison in {task}')

    # every task must be in the matrix
    indexed = set(cov.get('task_index', {}))
    for task in task_dirs:
        if task not in indexed:
            problems.append(f'task absent from matrix: {task}')
        elif not cov['task_index'][task]:
            problems.append(f'task claims no competencies: {task}')

    # metadata tags must be used by the contract (no decorative skills):
    # allowed tags = task id, category, slugs of claimed competencies' names
    tag_allow_global = {'clean-room', 'integrated'}
    for task in task_dirs:
        tp = ROOT / 'tasks' / task / 'task.toml'
        if not tp.exists():
            continue
        meta = read_toml(tp).get('metadata', {})
        tags = meta.get('tags', [])
        claimed = cov.get('task_index', {}).get(task, [])
        allowed = {task} | tag_allow_global
        if meta.get('category'):
            allowed.add(slug(str(meta['category'])))
        for cid in claimed:
            c = comps.get(cid, {})
            allowed.add(slug(c.get('name', '')))
            allowed |= {slug(v) for v in c.get('variants', [])}
        allowed.discard('')
        for tag in tags:
            t = tag.lower()
            if t in allowed or t.startswith('c-'):
                continue
            problems.append(f'{task}: tag {tag!r} not used by contract/verifier')

    covered = len(comps) - len(uncovered)
    print(f'competencies={len(comps)} covered={covered} '
          f'uncovered={len(uncovered)} problems={len(problems)}')
    for cid in uncovered:
        print('UNCOVERED', cid, comps[cid]['definition'][:90])
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
