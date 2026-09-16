#!/usr/bin/env python3
"""Normalize three authoring sources into a versioned, benchmark-free candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import re

PIPELINES = ('skills', 'repo', 'pr-issue')
COMMON = ('task_id', 'objective', 'acceptance', 'skills', 'source', 'author')


def validate(candidate):
    if not isinstance(candidate, dict):
        raise ValueError('candidate must be an object')
    if candidate.get('schema_version') != 1 or candidate.get('pipeline') not in PIPELINES:
        raise ValueError('unsupported schema_version or pipeline')
    for key in COMMON:
        if not candidate.get(key):
            raise ValueError(f'missing {key}')
    if not isinstance(candidate['task_id'], str) or not re.fullmatch(r'[a-z][a-z0-9-]{2,79}', candidate['task_id']):
        raise ValueError('task_id must be a safe lowercase slug')
    for key in ('objective', 'author'):
        if not isinstance(candidate[key], str) or not candidate[key].strip():
            raise ValueError(f'{key} must be nonempty text')
    for key in ('acceptance', 'skills'):
        if not isinstance(candidate[key], list) or not candidate[key] or any(not isinstance(x, str) or not x.strip() for x in candidate[key]):
            raise ValueError(f'{key} must contain nonempty strings')
    source = candidate['source']
    if not isinstance(source, dict) or source.get('benchmark_derived') is not False:
        raise ValueError('source.benchmark_derived must explicitly be false')
    required = {'skills': ('skill_paths', 'scenario', 'license'),
                'repo': ('repository', 'base_commit', 'license', 'workflow'),
                'pr-issue': ('repository', 'base_commit', 'license', 'reference', 'reproduction')}[candidate['pipeline']]
    for key in required:
        if not source.get(key):
            raise ValueError(f'source.{key} is required for {candidate["pipeline"]}')
        if key != 'skill_paths' and (not isinstance(source[key], str) or not source[key].strip()):
            raise ValueError(f'source.{key} must be nonempty text')
    if candidate['pipeline'] == 'skills':
        if not isinstance(source['skill_paths'], list) or any(not isinstance(x, str) or not x.strip() for x in source['skill_paths']):
            raise ValueError('source.skill_paths must contain paths')
    else:
        if not isinstance(source['base_commit'], str) or not re.fullmatch(r'[0-9a-f]{40}', source['base_commit']):
            raise ValueError('source.base_commit must be a full immutable commit')
        if 'fix_commit' in source and not re.fullmatch(r'[0-9a-f]{40}', str(source['fix_commit'])):
            raise ValueError('source.fix_commit must be a full immutable commit')
    return candidate


def fingerprint(task, candidate):
    digest = hashlib.sha256(json.dumps(candidate, sort_keys=True).encode())
    for path in sorted(task.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'symlinks are not allowed in new task packages: {path}')
        if path.is_file():
            digest.update(str(path.relative_to(task)).encode() + b'\0')
            digest.update(str(path.stat().st_mode & 0o777).encode() + b'\0')
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pipeline', choices=PIPELINES)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        candidate = json.loads(args.input.read_text())
        candidate.update(schema_version=1, pipeline=args.pipeline)
        validate(candidate)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x') as stream:
            stream.write(json.dumps(candidate, indent=2) + '\n')
    except (ValueError, OSError, TypeError, AttributeError) as exc:
        parser.exit(1, f'ERROR: {exc}\n')


if __name__ == '__main__':
    main()
