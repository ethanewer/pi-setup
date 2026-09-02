#!/usr/bin/env python3
"""Aggregate per-task difficulty evidence into specs/difficulty.json."""
import json, sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

ROOT = Path(__file__).resolve().parents[1]
RUBRIC_KEYS = ['dependent_stages', 'tool_breadth', 'reasoning_depth',
               'debugging_ambiguity', 'adversarial_inputs',
               'hidden_case_generalization', 'quantitative_correctness',
               'resource_pressure', 'interaction_statefulness',
               'unsafe_action_penalty']
BUCKETS = {'easy': (0, 9), 'medium': (10, 17), 'hard': (18, 30)}


def bucket_for(total: int) -> str:
    for name, (lo, hi) in BUCKETS.items():
        if lo <= total <= hi:
            return name
    return 'hard'


def main() -> int:
    times_path = ROOT / 'specs/oracle_times.json'
    times = json.loads(times_path.read_text()) if times_path.exists() else {}
    out_tasks = {}
    errors = []
    for d in sorted((ROOT / 'tasks').iterdir()):
        if not d.is_dir():
            continue
        dj = d / 'difficulty.json'
        if not dj.exists():
            errors.append(f'{d.name}: difficulty.json missing')
            continue
        dd = json.loads(dj.read_text())
        rub = dd.get('rubric', {})
        total = sum(rub.get(k, 0) for k in RUBRIC_KEYS)
        bucket = bucket_for(total)
        toml = tomllib.loads((d / 'task.toml').read_text())
        meta = toml.get('metadata', {})
        env = toml.get('environment', {})
        out_tasks[d.name] = {
            'rubric': {k: rub.get(k) for k in RUBRIC_KEYS},
            'total': total,
            'bucket': bucket,
            'task_toml_difficulty': meta.get('difficulty'),
            'expected_expert_time_min': dd.get('expected_expert_time_min'),
            'documented_probe': dd.get('documented_probe'),
            'oracle_time_sec': times.get(d.name, {}).get('oracle_time_sec'),
            'oracle_reward': times.get(d.name, {}).get('reward'),
            'verifier_timeout_sec': toml.get('verifier', {}).get('timeout_sec'),
            'agent_timeout_sec': toml.get('agent', {}).get('timeout_sec'),
            'memory_mb': env.get('memory_mb'),
            'cpus': env.get('cpus'),
            'notes': dd.get('notes', ''),
        }
    counts = {b: sum(1 for t in out_tasks.values() if t['bucket'] == b)
              for b in BUCKETS}
    out = {
        'version': 2,
        'rubric_dimensions': RUBRIC_KEYS,
        'rubric_scale': 'each dimension 0..3; total 0..30',
        'bucket_thresholds': BUCKETS,
        'suite_counts': counts,
        'tasks': out_tasks,
    }
    (ROOT / 'specs/difficulty.json').write_text(json.dumps(out, indent=2) + '\n')
    print(f'tasks={len(out_tasks)} buckets={counts} errors={len(errors)}')
    for e in errors:
        print('ERROR', e)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
