#!/usr/bin/env python3
"""Freeze/verify a pre-campaign baseline and validate a source inventory."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import sys

from campaign_control import validate_identity
from generate_tasks import ROOT, canonical_repository


BASELINE_ROOTS = (ROOT / 'tasks', ROOT / 'authoring/candidates')
BASELINE_FILES = (ROOT / 'specs/difficulty.json', ROOT / 'specs/coverage_claims.json')


def hash_file(path: Path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    return path, {'sha256': digest.hexdigest(), 'mode': path.stat().st_mode & 0o777,
                  'bytes': path.stat().st_size}


def snapshot(workers=min(8, os.cpu_count() or 1)):
    paths = []
    links = {}
    for root in BASELINE_ROOTS:
        for path in root.rglob('*'):
            if path.is_symlink():
                links[str(path.relative_to(ROOT))] = {
                          'symlink': os.readlink(path), 'mode': path.lstat().st_mode & 0o777}
            elif path.is_file():
                paths.append(path)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        records = dict(pool.map(hash_file, sorted(paths)))
    result = {str(path.resolve().relative_to(ROOT)): value for path, value in records.items()}
    result.update(links)
    return result


def source_report(path: Path):
    raw = json.loads(path.read_text())
    if isinstance(raw, dict) and isinstance(raw.get('sources'), list):
        sources = raw['sources']
        valid = [item for item in sources if item.get('eligible') is True
                 and re.fullmatch(r'[0-9a-f]{40}', str(item.get('revision', '')))
                 and item.get('license')]
        repositories = {canonical_repository(item['repository']) for item in valid}
        if len(repositories) < 200:
            raise ValueError(f'inventory has {len(repositories)} eligible repositories; at least 200 required')
        languages = {}
        for item in valid:
            for language in item.get('languages') or ['unknown']:
                languages[language] = languages.get(language, 0) + 1
        return {'eligible_repositories': len(repositories), 'sources': len(valid),
                'by_license': {value: sum(item['license'] == value for item in valid)
                               for value in sorted({item['license'] for item in valid})},
                'by_language': languages, 'csv_sha256': raw.get('csv_sha256')}
    if not isinstance(raw, list):
        raise ValueError('source inventory must be a discovery object or JSON identity list')
    identities = [validate_identity(item, canonical_repository) for item in raw]
    repositories = {item['repository'] for item in identities}
    if len(repositories) < 200:
        raise ValueError(f'inventory has {len(repositories)} eligible repositories; at least 200 required')
    by = lambda key: {value: sum(item[key] == value for item in identities)
                      for value in sorted({item[key] for item in identities})}
    return {'eligible_repositories': len(repositories), 'workflows': len(identities),
            'by_lane': by('lane'), 'by_language': by('language'),
            'by_domain': by('domain'), 'by_family': by('family')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    freeze = sub.add_parser('freeze')
    freeze.add_argument('--output', type=Path, required=True)
    freeze.add_argument('--workers', type=int, default=min(8, os.cpu_count() or 1))
    verify = sub.add_parser('verify')
    verify.add_argument('baseline', type=Path)
    verify.add_argument('--workers', type=int, default=min(8, os.cpu_count() or 1))
    inventory = sub.add_parser('sources')
    inventory.add_argument('inventory', type=Path)
    inventory.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'sources':
        report = source_report(args.inventory)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
        return 0
    current = snapshot(args.workers)
    if args.command == 'freeze':
        registries = {str(path.relative_to(ROOT)): json.loads(path.read_text())
                      for path in BASELINE_FILES}
        payload = {'schema_version': 2, 'root': str(ROOT), 'files': current,
                   'registries': registries}
        with args.output.open('x') as stream:
            stream.write(json.dumps(payload, indent=2) + '\n')
        print(f'frozen {len(current)} files')
        return 0
    baseline = json.loads(args.baseline.read_text())
    expected = baseline['files']
    added = sorted(set(current) - set(expected))
    removed = sorted(set(expected) - set(current))
    changed = sorted(path for path in set(current) & set(expected) if current[path] != expected[path])
    registry_changes = []
    for name, old in baseline.get('registries', {}).items():
        new = json.loads((ROOT / name).read_text())
        if name.endswith('difficulty.json'):
            old_entries, new_entries = old.get('tasks', {}), new.get('tasks', {})
        else:
            old_entries, new_entries = old, new
        for key, value in old_entries.items():
            if new_entries.get(key) != value:
                registry_changes.append(f'{name}:{key}')
    result = {'baseline_unchanged': not (removed or changed or registry_changes),
              'added': added, 'removed': removed, 'changed': changed,
              'changed_registry_entries': registry_changes}
    print(json.dumps(result, indent=2))
    return 0 if result['baseline_unchanged'] else 1


if __name__ == '__main__':
    sys.exit(main())
