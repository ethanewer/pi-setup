#!/usr/bin/env python3
"""Record provenance for every task-owned file (TODO.md section 3.3).

Every non-boilerplate file under tasks/, tools/, agents/ and the spec files
gets an entry: origin, license, transformation history, final SHA-256.
Default policy for v2 is zero shared source repositories: external_sources
must stay empty, and the independence audit compares repository identities
against the reference provenance set rather than trusting this list alone.

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
        return 'authored-clean-room-v2'
    if rel.startswith(('tools/', 'agents/')):
        return 'authored-clean-room-v2-tooling'
    return 'authored-clean-room-v2-spec'


def main() -> int:
    files = {}
    spec_runtime = {'provenance.json', 'independence_report.json',
                    'similarity_report.json', 'oracle_report.json',
                    'oracle_times.json'}
    for p in sorted((ROOT / 'specs').glob('*.json')):
        if p.name in spec_runtime:
            continue
        rel = str(p.relative_to(ROOT))
        files[rel] = {
            'origin': 'authored-clean-room-v2-spec',
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
    policy = ('clean-room; zero shared source repositories with the '
              'frozen reference provenance set')
    if upstream_path.exists():
        up = json.loads(upstream_path.read_text())
        external = [{'repository': r, 'url': f'https://{r}',
                     'used_by': sorted(e['task'] for e in up.get('tasks', [])
                                       if r in e.get('repositories', [])),
                     'fetched_at': 'image build time (environment/Dockerfile); '
                                   'never committed to this tree'}
                    for r in up.get('repositories', [])]
        policy = ('clean-room for every authored fixture; from v4.2 some tasks '
                  'also clone upstream repositories at image-build time, listed in '
                  'external_sources. No listed repository is shared with the '
                  'frozen reference provenance set; '
                  'tools/check_upstream_disjointness.py enforces that against '
                  'specs/tb21_source_repositories.json')
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
