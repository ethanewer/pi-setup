#!/usr/bin/env python3
"""Record provenance for every task-owned file (TODO.md section 3.3).

Every non-boilerplate file under tasks/, tools/, agents/ and the spec files
gets an entry: origin, license, transformation history, final SHA-256.
Source receipts are recorded by authoring; contamination is checked in QA.

Run this AFTER task content is frozen, then run the audits.
"""
import datetime, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def origin_for(rel: str) -> str:
    if rel.startswith('tasks/'):
        return 'general-task'
    if rel.startswith(('tools/', 'agents/')):
        return 'general-tooling'
    return 'general-spec'


def main() -> int:
    files = {}
    spec_runtime = {'provenance.json', 'independence_report.json',
                    'similarity_report.json', 'oracle_report.json',
                    'oracle_times.json'}
    # rglob over every file, not just *.json: check_reproducibility.py walks
    # OWNED with rglob('*'), so a narrower pattern here silently omits anything
    # else and the two tools disagree. specs/ held only .json files until
    # specs/v43_issue_pool/ added a subdirectory with a README.md, which exposed
    # both gaps at once -- 60 json files missed by a non-recursive glob, then the
    # README missed by a json-only one.
    for p in sorted((ROOT / 'specs').rglob('*')):
        if not p.is_file() or '__pycache__' in p.parts:
            continue
        if p.name in spec_runtime:
            continue
        rel = str(p.relative_to(ROOT))
        files[rel] = {
            'origin': 'general-spec',
            'source_repository': None,
            'source_commit': None,
            'license': 'internal (authored for general-v2)',
            'transformation': 'derived from private audit records',
            'sha256': sha_file(p),
        }
    for sub in ('tasks', 'tools', 'agents'):
        base = ROOT / sub
        for p in sorted(base.rglob('*')):
            if not p.is_file() or '__pycache__' in p.parts:
                continue
            rel = str(p.relative_to(ROOT))
            try:
                h = sha_file(p)
            except OSError:
                h = 'unreadable-mode-restricted-fixture'
            files[rel] = {
                'origin': origin_for(rel),
                'source_repository': None,
                'source_commit': None,
                'license': 'internal (authored for general-v2)',
                'transformation': 'hand-authored' if rel.startswith('tasks/')
                                  else 'authored tooling',
                'sha256': h,
            }
    # Upstream repositories cloned at image-build time, if any task declares them.
    # tools/check_upstream_disjointness.py --apply derives this from the build path
    # of every task and enforces that none of them is shared with the frozen
    # reference. Carrying it here is what makes audit_independence_stream.py's
    # source_repository class mean something: that check intersects our
    # external_sources with a --reference-provenance list, and until the v4.2
    # family existed this was always empty, so the class was vacuous rather than
    # passing.
    upstream_path = ROOT / 'specs' / 'upstream_sources.json'
    external = []
    policy = 'Source provenance recorded independently; contamination clearance requires QA.'
    if upstream_path.exists():
        up = json.loads(upstream_path.read_text())
        external = [{'repository': r, 'url': f'https://{r}',
                     'used_by': sorted(e['task'] for e in up.get('tasks', [])
                                       if r in e.get('repositories', [])),
                     'fetched_at': 'image build time (environment/Dockerfile); '
                                   'never committed to this tree'}
                    for r in up.get('repositories', [])]
    manifest = {
        'policy': policy,
        'external_sources': external,
        'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'task_files': files,
    }
    (ROOT / 'specs/provenance.json').write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    print(f'recorded {len(files)} files, {len(external)} external source '
          f'repositories')
    return 0


if __name__ == '__main__':
    sys.exit(main())
