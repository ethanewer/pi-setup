#!/usr/bin/env python3
"""Build a bounded, no-checkout GitHub source inventory from the campaign CSV."""
import argparse
import concurrent.futures
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.request

from generate_tasks import canonical_repository


def inspect(row):
    try:
        repository = canonical_repository(row['github_url'])
        remote = subprocess.run(['git', 'ls-remote', '--symref', repository + '.git', 'HEAD'],
                                text=True, capture_output=True, timeout=30)
        if remote.returncode:
            raise ValueError('unavailable')
        branch_match = re.search(r'^ref: refs/heads/([^\s]+)\s+HEAD$', remote.stdout, re.M)
        sha_match = re.search(r'^([0-9a-f]{40})\s+HEAD$', remote.stdout, re.M)
        if not branch_match or not sha_match:
            raise ValueError('HEAD is not an immutable commit')
        request = urllib.request.Request(repository, headers={'User-Agent': 'general-eval-source-inventory/1'})
        html = urllib.request.urlopen(request, timeout=30).read().decode('utf-8', 'replace')
        license_match = re.search(r'"license","tabName":"([^"]+)"', html)
        if not license_match or license_match.group(1).lower() in ('license', 'view license', 'other', 'no license'):
            raise ValueError('license not machine-verifiable')
        languages = re.findall(r'itemprop="programmingLanguage">\s*([^<]+)', html)
        return {'name': row['name'].strip(), 'repository': repository,
                'revision': sha_match.group(1), 'default_branch': branch_match.group(1),
                'license': license_match.group(1),
                'languages': sorted(set(value.strip().lower() for value in languages if value.strip())),
                'availability_check': 'git ls-remote --symref REPOSITORY HEAD',
                'license_check': 'GitHub repository license metadata', 'eligible': True}
    except Exception as exc:
        return {'name': row.get('name', '').strip(), 'repository': row.get('github_url', '').strip(),
                'eligible': False, 'reason': str(exc)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--csv', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rejections', type=Path, required=True)
    parser.add_argument('--workers', type=int, default=32)
    parser.add_argument('--limit', type=int, default=240)
    args = parser.parse_args()
    with args.csv.open(encoding='utf-8-sig', newline='') as stream:
        rows = [row for row in csv.DictReader(stream) if row.get('github_url', '').strip()]
    unique = {}
    for row in rows:
        try:
            unique.setdefault(canonical_repository(row['github_url']), row)
        except ValueError:
            pass
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(inspect, list(unique.values())[:args.limit]))
    accepted = sorted((item for item in results if item['eligible']), key=lambda x: x['repository'])
    rejected = [item for item in results if not item['eligible']]
    payload = {'schema_version': 1, 'csv': str(args.csv.resolve()),
               'csv_sha256': hashlib.sha256(args.csv.read_bytes()).hexdigest(),
               'sources': accepted}
    args.output.write_text(json.dumps(payload, indent=2) + '\n')
    args.rejections.write_text(json.dumps(rejected, indent=2) + '\n')
    print(json.dumps({'checked': len(results), 'eligible': len(accepted),
                      'rejected': len(rejected)}, indent=2))
    return 0 if len(accepted) >= 200 else 1


if __name__ == '__main__':
    raise SystemExit(main())
