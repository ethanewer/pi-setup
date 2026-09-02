#!/usr/bin/env python3
"""Freeze the Terminal-Bench reference checkout into the private audit record.

This tool READS the external reference checkout but never copies any of its
content into the v2 tree.  It writes:

  private-audit/frozen_manifest.json   exact per-task manifest (private)
  specs/frozen_reference.json          pointer + checkout identity (config)

The frozen manifest is the audit ground truth.  Audit tools fail closed when
the checkout on disk no longer matches the frozen identity.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / 'private-audit'

try:
    import yaml  # optional; task.yaml parsing
except ImportError:
    yaml = None


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(['git', '-C', str(repo), *args],
                                   text=True).strip()


def parse_task_yaml(p: Path) -> dict:
    text = p.read_text(errors='replace')
    if yaml is not None:
        try:
            return yaml.safe_load(text) or {}
        except Exception:
            pass
    # Minimal fallback: top-level scalar keys only.
    out = {}
    for line in text.splitlines():
        if line and not line[0].isspace() and ':' in line:
            k, _, v = line.partition(':')
            out[k.strip()] = v.strip()
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--reference-root', type=Path,
                    default=Path('/home/eewer/agent-collab/terminal-bench'))
    ap.add_argument('--verify', action='store_true',
                    help='fail closed unless the checkout still matches the '
                         'frozen identity (does not rewrite the manifest)')
    args = ap.parse_args()

    repo = args.reference_root
    tasks_root = repo / 'original-tasks'
    if not tasks_root.is_dir():
        print(f'ERROR: {tasks_root} not found', file=sys.stderr)
        return 1

    commit = git(repo, 'rev-parse', 'HEAD')
    commit_date = git(repo, 'log', '-1', '--format=%cI')

    cfg_path = ROOT / 'specs/frozen_reference.json'
    if args.verify:
        if not cfg_path.exists():
            print('ERROR specs/frozen_reference.json missing; run without '
                  '--verify first')
            return 1
        cfg = json.loads(cfg_path.read_text())
        if cfg['commit'] != commit:
            print(f'ERROR checkout commit {commit} != frozen {cfg["commit"]}')
            return 1
        print(f'reference identity verified: commit={commit[:12]}, '
              f'{cfg["task_count"]} tasks')
        return 0

    remote = ''
    try:
        remote = git(repo, 'remote', 'get-url', 'origin')
    except subprocess.CalledProcessError:
        pass
    # Deterministic identity of the task checkout itself (independent of the
    # surrounding repo state): merkle over sorted relative path + file hash.
    entries = []
    task_names = sorted(p.name for p in tasks_root.iterdir() if p.is_dir())
    for name in task_names:
        d = tasks_root / name
        for f in sorted(d.rglob('*')):
            if f.is_file():
                entries.append((str(f.relative_to(tasks_root)), sha256_file(f)))
    h = hashlib.sha256()
    for rel, fh in entries:
        h.update(f'{rel}\x00{fh}\x00'.encode())
    checkout_hash = h.hexdigest()

    manifest_tasks = {}
    for name in task_names:
        d = tasks_root / name
        files = {str(f.relative_to(d)): sha256_file(f)
                 for f in sorted(d.rglob('*')) if f.is_file()}
        meta = {}
        ty = d / 'task.yaml'
        if ty.exists():
            raw = parse_task_yaml(ty)
            for k in ('difficulty', 'category', 'tags', 'parser_name',
                      'max_agent_timeout_sec', 'max_test_timeout_sec',
                      'expert_time_estimate_min', 'junior_time_estimate_min',
                      'author_name'):
                if isinstance(raw, dict) and k in raw:
                    meta[k] = raw[k]
        size = sum((d / rel).stat().st_size for rel in files)
        manifest_tasks[name] = {
            'path': f'original-tasks/{name}',
            'sha256_files': files,
            'bytes': size,
            'metadata': meta,
        }

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    manifest = {
        'reference': 'Terminal-Bench (laude-institute/terminal-bench)',
        'suite_pin_note': ('Pinned checkout used as the Terminal-Bench 2.1 '
                           'competency reference for general-v2. Content is '
                           'never copied into the v2 tree.'),
        'repository': remote,
        'commit': commit,
        'commit_date': commit_date,
        'frozen_at': now,
        'task_checkout_sha256': checkout_hash,
        'task_count': len(task_names),
        'file_count': len(entries),
        'tasks': manifest_tasks,
    }

    AUDIT.mkdir(parents=True, exist_ok=True)
    (AUDIT / 'frozen_manifest.json').write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    (ROOT / 'specs').mkdir(exist_ok=True)
    (ROOT / 'specs/frozen_reference.json').write_text(json.dumps({
        'reference': manifest['reference'],
        'repository': remote,
        'commit': commit,
        'commit_date': commit_date,
        'task_checkout_sha256': checkout_hash,
        'task_count': len(task_names),
        'frozen_at': now,
        'reference_root': str(tasks_root),
        'policy': ('Audit tools must resolve the reference from this file '
                   'when --reference-root is omitted and must fail closed if '
                   'the checkout identity no longer matches.'),
    }, indent=2) + '\n')
    print(f'frozen: {len(task_names)} tasks, commit={commit[:12]}, '
          f'checkout_sha256={checkout_hash[:16]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
