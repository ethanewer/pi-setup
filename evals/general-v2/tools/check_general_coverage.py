#!/usr/bin/env python3
"""General-inventory coverage gate.

Decision D1 (private-audit/DECISIONS.md): the optional General skill inventory
is NOT retained in v2.  TODO.md permits removing the claim that generic probes
test the corresponding skills.  This gate verifies the "not retained" state:

  - no general_skill_coverage.json
  - no probe tasks
  - no metadata anywhere claiming General-skill coverage

If the inventory is ever retained again, the strict equality rule applies:
unique skills in skills.json == entries in general_skill_coverage.json ==
existing verifier-backed v2 tasks.  Re-implement the strict mode then.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors = []

cov = ROOT / 'specs/general_skill_coverage.json'
if cov.exists():
    errors.append('general_skill_coverage.json exists but the General inventory '
                  'is not retained (decision D1); remove it or implement strict mode')

probes = sorted(p.name for p in (ROOT / 'tasks').glob('probe-*'))
if probes:
    errors.append(f'{len(probes)} probe tasks exist without real skill coverage: '
                  f'{probes[:3]}...')

for d in sorted((ROOT / 'tasks').iterdir()):
    if not d.is_dir():
        continue
    for f in ('task.toml', 'instruction.md'):
        p = d / f
        if p.exists() and 'clean-room-probe' in p.read_text(errors='replace'):
            errors.append(f'{d.name}/{f} still carries the probe claim tag')

print(f'general_inventory=not-retained errors={len(errors)}')
for e in errors:
    print('ERROR', e)
sys.exit(bool(errors))
