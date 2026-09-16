#!/usr/bin/env python3
"""Every task file must be reachable from a fresh clone.

A task directory can contain a file that the build, the verifier or the oracle
depends on and that git will never carry, because something ignores it. The
ignoring rule is usually not the repository's own: it is a `.gitignore` an
author wrote inside the task for a reason that only applies inside the
container.

This has broken the suite twice.

The first time, the repository-root `.gitignore` patterns `*.log` and
`evals/**/results/` matched 65 `.log` fixtures and 74 files under directories
named `results/`. A fresh clone was missing all 139, which left kiln-anchor and
larch-vane with an empty `tests/hidden` and 145 provenance entries pointing at
files that did not exist. That was fixed with negations in
`evals/general/.gitignore` and a comment explaining why they are there.

The second time, in the v4.1 wave, `stanchion-bell` shipped
`environment/files/.gitignore` listing `scripts/make_repo.sh`. The author's
intent was in-container: the Dockerfile copies `files/` to `/app` and runs that
script to build a git history, and ignoring it there keeps the agent's own
`git status` clean, which the script's header comment says outright. The same
file also excludes the script from the repository, so line 22 of the Dockerfile
runs a path that a clone does not have. The task passed its own oracle and
negative control on the machine that authored it, because the file was on disk.

A negation in `evals/general/.gitignore` cannot fix that case: a pattern in a
deeper `.gitignore` takes precedence over a shallower one, so the task-local
file wins. Force-tracking does, because once git tracks a path its ignore rules
no longer apply to it, and the in-container behaviour is unchanged.

Gate: every file under `tasks/` is either tracked by git, or declared in
`specs/large_assets.json` (the five vendored upstream distributions, fetched by
sha256 and listed so a clone knows what to obtain), or is compiled debris
(`__pycache__`, `*.pyc`). Anything else is a file a clone will not have.

Usage:
  python3 tools/check_task_files_tracked.py            # gate
  python3 tools/check_task_files_tracked.py --verbose  # list every ignored path
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'
DEBRIS_DIRS = {'__pycache__', '.git', 'node_modules'}
DEBRIS_SUFFIX = {'.pyc', '.pyo'}


def tracked_files() -> set[str]:
    """Paths git tracks under tasks/, relative to the suite root."""
    out = subprocess.run(
        ['git', 'ls-files', '-z', '--', 'tasks'],
        cwd=ROOT, capture_output=True, check=True).stdout
    return {p for p in out.decode('utf-8', 'replace').split('\0') if p}


def declared_large_assets() -> set[str]:
    spec = ROOT / 'specs' / 'large_assets.json'
    if not spec.exists():
        return set()
    try:
        data = json.loads(spec.read_text())
    except Exception as e:
        raise SystemExit(f'specs/large_assets.json is not valid JSON: {e}')
    return {a['repo_path'] for a in data.get('assets', []) if 'repo_path' in a}


def disk_files() -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(TASKS):
        dirnames[:] = [d for d in dirnames if d not in DEBRIS_DIRS]
        for f in filenames:
            if os.path.splitext(f)[1] in DEBRIS_SUFFIX:
                continue
            p = Path(dirpath) / f
            out.append(str(p.relative_to(ROOT)))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    tracked = tracked_files()
    declared = declared_large_assets()
    on_disk = disk_files()

    missing = sorted(p for p in on_disk if p not in tracked and p not in declared)
    # the mirror image also matters: provenance or a Dockerfile can name a path
    # that no longer exists on disk, which is how the first incident showed up
    stale_declared = sorted(p for p in declared
                            if not (ROOT / p).exists())

    print(f'task_files_on_disk={len(on_disk)} tracked={len(tracked)} '
          f'declared_large_assets={len(declared)} '
          f'untracked_and_undeclared={len(missing)} '
          f'declared_but_absent={len(stale_declared)}')

    if args.verbose:
        for p in missing:
            print('UNTRACKED', p)

    problems = 0
    for p in missing:
        # name the ignore rule, because the fix depends on which file it is in
        why = subprocess.run(['git', 'check-ignore', '-v', str(ROOT / p)],
                             cwd=ROOT, capture_output=True, text=True).stdout.strip()
        print(f'ERROR {p} is on disk but a fresh clone will not have it')
        if why:
            print(f'      ignored by: {why}')
        else:
            print('      not matched by any ignore rule; it was simply never added')
        problems += 1
    for p in stale_declared:
        print(f'ERROR specs/large_assets.json declares {p} but it is not on disk')
        problems += 1

    if problems:
        print(f'\n{problems} problem(s). A task whose build, verifier or oracle '
              f'needs an untracked file passes on the machine that authored it '
              f'and fails on every clone. Fix by force-tracking the path '
              f'(`git add -f`) when the ignore rule is meant to apply only '
              f'inside the container, by removing the rule when it is not '
              f'wanted at all, or by declaring the path in '
              f'specs/large_assets.json when it is a large asset fetched '
              f'separately.')
        return 1
    print('every task file is reachable from a fresh clone')
    return 0


if __name__ == '__main__':
    sys.exit(main())
