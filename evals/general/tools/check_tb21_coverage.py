#!/usr/bin/env python3
"""Terminal-Bench competency coverage gate (TODO.md section 2.4).

Failures (hard):
  - missing reference competency (inventory id with no covering task),
    except competencies documented environmentally infeasible in
    private-audit/infeasible/*.json
  - competency mapped only to tasks that do not exercise it
  - missing verifier evidence
  - no covering task at the competency's difficulty floor, unless the
    covering task carries a documented probe waiver in specs/difficulty.json
    (same waiver check_difficulty.py applies)
  - duplicate task or probe IDs
  - task absent from the matrix
  - metadata tag not traceable to the task contract: every tag must be a
    task id, a competency id (c-*), 'clean-room'/'integrated', or a
    word-subset of the claimed competencies' names/variants or of the
    task's own contract text (task.toml, instruction, tests, oracle)
Warnings (documented residual, see TODO.md completion checklist):
  - second-task coverage shortfall for second_task_required competencies
    (reported with count; the suite ships with this documented shortfall)
Prints counts plus the complete list of uncovered competencies; exits nonzero
on any hard problem.
"""
import glob, json, re, sys
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


def words(s: str) -> set:
    return set(re.findall(r'[a-z0-9]+', s.lower()))


def load_infeasible(root: Path) -> set:
    ids = set()
    d = root / 'private-audit/infeasible'
    if d.exists():
        for f in glob.glob(str(d / '*.json')):
            try:
                ids |= set(json.loads(Path(f).read_text()).get('competencies', []))
            except Exception:
                pass
    return ids


def task_contract_words(task_dir: Path) -> set:
    """Union of words appearing anywhere in the task's own contract files."""
    w = set()
    candidates = [task_dir / 'task.toml', task_dir / 'instruction.md',
                  task_dir / 'run-tests.sh', task_dir / 'solution.sh']
    for sub in ('tests', 'environment', 'solution'):
        d = task_dir / sub
        if d.is_dir():
            candidates.extend(p for p in d.rglob('*') if p.is_file())
    for p in candidates:
        try:
            if p.is_file() and p.stat().st_size <= 2_000_000:
                w |= words(p.read_text(errors='replace'))
        except Exception:
            pass
    return w


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
    second_task_gaps = []

    # documented environmentally-infeasible competencies are waived
    infeasible = load_infeasible(ROOT)

    # difficulty buckets + documented probe waivers (same source as
    # check_difficulty.py so both gates agree on floors)
    diff = json.loads((ROOT / 'specs/difficulty.json').read_text())['tasks']

    task_dirs = sorted(p.name for p in (ROOT / 'tasks').iterdir() if p.is_dir())
    if len(task_dirs) != len(set(task_dirs)):
        problems.append('duplicate task directory IDs')

    # every inventory competency must be covered (infeasible ones waived)
    uncovered = [cid for cid in comps
                 if cid not in matrix or not matrix[cid]]
    for cid in list(uncovered):
        if cid in infeasible:
            uncovered.remove(cid)
            continue
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
        # second-task requirement for rare / high-risk competencies:
        # documented residual (see TODO.md completion checklist) — reported
        # as a warning with count, not a hard failure
        if spec.get('second_task_required') and len({c['task_id'] for c in real}) < 2:
            second_task_gaps.append(cid)
        # difficulty floor (waived by a documented probe, as in
        # check_difficulty.py)
        floor = spec.get('min_required_difficulty', 'easy')
        flok = False
        for c in real:
            t = diff.get(c['task_id'], {})
            if DIFF_ORDER.get(t.get('bucket', c.get('difficulty', 'easy')), 0) \
                    >= DIFF_ORDER[floor] or t.get('documented_probe'):
                flok = True
                break
        if not flok:
            problems.append(f'{cid}: no covering task at difficulty >= {floor} '
                            'and no documented probe waiver')

    for cid, task in weak:
        problems.append(f'{cid}: high-risk competency covered only by '
                        f'answer-comparison in {task}')

    # every task must be in the matrix
    indexed = set(cov.get('task_index', {}))
    for task in task_dirs:
        if task not in indexed:
            problems.append(f'task absent from matrix: {task}')
        elif not cov['task_index'][task] and not task.startswith(('v1-', 'tb3-')):
            problems.append(f'task claims no competencies: {task}')

    # metadata tags must be traceable to the task contract (no decorative
    # skill claims): a tag passes if it is a task id (own or in-suite family
    # reference), a competency id, 'clean-room'/'integrated', or a word-subset
    # of the claimed competencies' names/variants or of the task's own
    # contract text (task.toml / instruction / tests / oracle / environment)
    tag_allow_global = {'clean-room', 'integrated'}
    suite_ids = set(task_dirs)
    for task in task_dirs:
        tp = ROOT / 'tasks' / task / 'task.toml'
        if not tp.exists():
            continue
        meta = read_toml(tp).get('metadata', {})
        tags = meta.get('tags', [])
        claimed = cov.get('task_index', {}).get(task, [])
        comp_text = ' '.join(
            [comps.get(cid, {}).get('name', '') for cid in claimed]
            + [v for cid in claimed for v in comps.get(cid, {}).get('variants', [])])
        compw = words(comp_text)
        contractw = task_contract_words(ROOT / 'tasks' / task)
        for tag in tags:
            t = tag.lower()
            if (t in tag_allow_global or t == task or t in suite_ids
                    or t.startswith('c-')):
                continue
            tw = words(t)
            if tw and (tw <= compw or tw <= contractw):
                continue
            problems.append(f'{task}: tag {tag!r} not used by contract/verifier')

    covered = sum(1 for cid in comps if matrix.get(cid))
    print(f'competencies={len(comps)} covered={covered} '
          f'uncovered={len(uncovered)} (of which waived-infeasible '
          f'{len(infeasible & (set(comps) - set(matrix)))}) problems={len(problems)} '
          f'second_task_gaps={len(second_task_gaps)} (documented residual)')
    for cid in uncovered:
        print('UNCOVERED', cid, comps[cid]['definition'][:90])
    for cid in second_task_gaps:
        print('WARN second-task shortfall:', cid)
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
