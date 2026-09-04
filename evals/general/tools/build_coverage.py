#!/usr/bin/env python3
"""Build specs/coverage.json from authored claims and task contracts.

Input:  specs/coverage_claims.json (authored; task -> competency IDs + evidence)
Input:  specs/tb21_competencies.json (inventory)
Input:  tasks/*/task.toml (verifier_kind, deliverables, difficulty)
Output: specs/coverage.json (validated task-to-competency matrix)
"""
import json, sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

ROOT = Path(__file__).resolve().parents[1]


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


def main() -> int:
    errors = []
    inv_path = ROOT / 'specs/tb21_competencies.json'
    claims_path = ROOT / 'specs/coverage_claims.json'
    if not inv_path.exists():
        print('ERROR specs/tb21_competencies.json missing'); return 1
    if not claims_path.exists():
        print('ERROR specs/coverage_claims.json missing'); return 1
    inv = json.loads(inv_path.read_text())
    known = {c['id'] for c in inv['competencies']}
    claims = json.loads(claims_path.read_text())

    tasks_dir = ROOT / 'tasks'
    task_ids = sorted(p.name for p in tasks_dir.iterdir() if p.is_dir())
    if len(task_ids) != len(set(task_ids)):
        errors.append('duplicate task IDs')

    matrix = {}
    task_index = {}
    skipped = []
    for task in task_ids:
        toml_path = tasks_dir / task / 'task.toml'
        if not toml_path.exists():
            skipped.append(task)  # mid-authoring directory; lint enforces completeness
            continue
        toml = read_toml(toml_path)
        meta = toml.get('metadata', {})
        vkind = meta.get('verifier_kind', '')
        deliverables = meta.get('deliverables', [])
        hidden_exempt = bool(meta.get('hidden_cases_exempt', ''))
        hidden_dir = tasks_dir / task / 'tests/hidden'
        hidden = hidden_dir.is_dir() or hidden_exempt
        if task not in claims:
            errors.append(f'{task}: absent from coverage_claims.json')
            continue
        entry = claims[task]
        ids = entry.get('competencies', [])
        evidence = entry.get('evidence', {})
        if not isinstance(evidence, dict):
            evidence = {cid: str(evidence) for cid in ids}
        if not ids and not task.startswith('v1-') and not entry.get('claims_no_competencies'):
            # v1-* tasks are the imported legacy general-coding family;
            # supplementary skill-coverage tasks declare an explicit
            # claims_no_competencies flag in coverage_claims.json (same
            # exemption check_tb21_coverage.py grants).
            errors.append(f'{task}: claims no competencies')
        task_index[task] = ids
        for cid in ids:
            if cid not in known:
                errors.append(f'{task}: unknown competency id {cid}')
                continue
            ev = evidence.get(cid, '')
            cell = {
                'task_id': task,
                'evidence': ev,
                'verifier_kind': vkind,
                'deliverables': deliverables,
                'hidden_cases': hidden,
                'difficulty': meta.get('difficulty', ''),
            }
            matrix.setdefault(cid, []).append(cell)

    out = {
        'version': 3,
        'policy': ('Task-to-competency matrix. Competency IDs are opaque; the '
                   'private mapping to reference evidence lives in '
                   'private-audit/competency_map.json.'),
        'competency_count': len(known),
        'task_count': len(task_ids),
        'matrix': matrix,
        'task_index': task_index,
    }
    (ROOT / 'specs/coverage.json').write_text(json.dumps(out, indent=2) + '\n')
    print(f'tasks={len(task_ids)} competencies={len(known)} '
          f'claimed_cells={sum(len(v) for v in matrix.values())} '
          f'errors={len(errors)} skipped_mid_authoring={len(skipped)}')
    for e in errors:
        print('ERROR', e)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
