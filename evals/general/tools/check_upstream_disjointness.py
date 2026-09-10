#!/usr/bin/env python3
"""Upstream-clone disjointness and pinning gate.

The v4.2 family clones real upstream repositories at image-build time so tasks
can put an agent inside a production codebase, which is what Terminal-Bench 2.1
does in 42 of its 241 tasks and what this suite did in none of its first 837.
Two invariants make that safe, and neither is enforceable by reading a policy
sentence in WORKFLOW.md.

1. DISJOINTNESS. No task may clone, download, submodule or pip-install-from-git
   any repository the frozen Terminal-Bench 2.1 reference also uses. That list is
   `specs/tb21_source_repositories.json`, extracted from every text file under the
   reference's `original-tasks/` -- 68 repositories across 79 of its tasks. Two
   suites sharing an upstream repository is how a clean-room claim dies, and it is
   invisible in a byte-level audit when the bytes are fetched at build time and
   never enter either tree.

2. PINNING. Every clone must resolve to one immutable revision. `RUN git clone
   https://github.com/x/y` builds a different environment every day the upstream
   moves, which is the same defect `pin_python_dependencies.py` exists to prevent
   for pip: the committed Dockerfile stops reproducing the task that was measured.
   A pin is either `--branch <tag>` plus an assertion that HEAD is the expected
   40-hex commit, or an explicit `git checkout <40-hex>`. A bare tag alone is
   accepted but warned about, because tags can be force-moved; a SHA cannot.

Also enforced: the clone must be in the build path (`environment/Dockerfile` or a
script under `environment/`), never in `tests/` or `solution/`, because the trial
container runs with no network and a clone there cannot work. And `--depth` is
required, because a full history for a repository the size of apache/kafka turns a
task image into gigabytes for no benefit.

Not machine-checked, and worth knowing: nothing here detects an author who
*vendors* a copy of an upstream tree into `environment/files` instead of cloning
it. That would put upstream bytes inside the audited tree, where the block and
n-gram classes of `audit_independence_stream.py` can see them, so the byte audit
is the backstop rather than this gate.

Usage:
  python3 tools/check_upstream_disjointness.py            # gate
  python3 tools/check_upstream_disjointness.py --apply    # also write specs/upstream_sources.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'
FORBIDDEN_SPEC = ROOT / 'specs' / 'tb21_source_repositories.json'
INVENTORY = ROOT / 'specs' / 'upstream_sources.json'

# git+https, https, git@ and ssh forms, plus pip's VCS form.
URL = re.compile(
    r'(?:git\+)?(?:https?://|git@|ssh://git@)'
    r'(github\.com|gitlab\.com|bitbucket\.org)[:/]'
    r'([A-Za-z0-9_.\-]+)/([A-Za-z0-9_.\-]+?)(?:\.git)?'
    r'(?:[@/#?][^\s"\'`)\]]*)?(?=[\s"\'`)\],;]|$)')
CLONE_LINE = re.compile(r'git\s+clone\b[^\n]*')
# An actual VCS fetch, as opposed to a URL that is merely data. fern-hearth ships
# tests/hidden/urls_basic.txt full of invented repository URLs because the task is
# URL normalisation; matching on the URL alone condemned it, so the trial-path rule
# requires a command.
VCS_FETCH = re.compile(
    r'\bgit\s+(clone|fetch|pull|submodule\s+update|remote\s+add)\b'
    r'|\bpip3?\s+install\b[^\n]*\bgit\+'
    r'|\bnpm\s+install\b[^\n]*(github:|git\+)', re.I)
# A clone of a loopback or filesystem path needs no external network and is how
# this suite's git-workflow tasks are verified: hollow-atlas clones
# gitops@localhost:/srv/git/atlas.git, v1-skill-git-over-ssh clones
# sshgit@127.0.0.1:/home/sshgit/repos/team.git, thwart-lantern clones a local
# path. Only an internet host in the trial path is impossible.
REMOTE_HOST = re.compile(
    r'(?:https?://|git\+https?://|ssh://)'
    r'(?!localhost\b|127\.0\.0\.1|0\.0\.0\.0|\[::1\])'
    r'[A-Za-z0-9_.\-]+\.[A-Za-z]{2,}'
    r'|\bgit@(?!localhost\b|127\.0\.0\.1)[A-Za-z0-9_.\-]+\.[A-Za-z]{2,}', re.I)


def trial_fetches_internet(text: str):
    """Return the first VCS command in the trial path that names an internet host."""
    for line in text.splitlines():
        if VCS_FETCH.search(line) and REMOTE_HOST.search(line):
            return line.strip()[:100]
    return None
SHA40 = re.compile(r'\b[0-9a-f]{40}\b')
# hosts that are package or artifact mirrors rather than source repositories;
# a task may fetch a released wheel or tarball from these without it being an
# upstream source clone. Recorded separately so the inventory stays honest.
NON_SOURCE_HINT = re.compile(
    r'(pypi\.org|files\.pythonhosted\.org|registry\.npmjs\.org|crates\.io|'
    r'repo\.maven\.apache\.org|proxy\.golang\.org|releases\.hashicorp\.com|'
    r'download\.pytorch\.org|objects\.githubusercontent\.com|codeload\.github\.com)', re.I)


def norm(host: str, owner: str, name: str) -> str:
    return f'{host.lower()}/{owner.lower()}/{name.lower().removesuffix(".git")}'


def load_forbidden():
    if not FORBIDDEN_SPEC.exists():
        raise SystemExit(f'ERROR {FORBIDDEN_SPEC} missing; cannot enforce disjointness')
    data = json.loads(FORBIDDEN_SPEC.read_text())
    return {t['repository'].lower() for t in data['tasks']}, data


def build_text(tdir: Path) -> tuple[str, str]:
    """(build-path text, trial-path text) for one task."""
    build, trial = [], []
    env = tdir / 'environment'
    for base, sink in ((env, build), (tdir / 'tests', trial), (tdir / 'solution', trial)):
        if not base.is_dir():
            continue
        for dp, dn, fn in os.walk(base):
            dn[:] = [d for d in dn if d not in ('.git', '__pycache__', 'node_modules')]
            for f in fn:
                p = Path(dp) / f
                if f.endswith(('.md', '.json', '.csv', '.tsv', '.npy', '.npz',
                               '.parquet', '.png', '.jpg', '.bin', '.db')):
                    continue
                try:
                    if p.stat().st_size > 2_000_000:
                        continue
                    s = p.read_text(errors='replace')
                except OSError:
                    continue
                if '\x00' in s[:2048]:
                    continue
                sink.append(s)
    return '\n'.join(build), '\n'.join(trial)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true',
                    help='write specs/upstream_sources.json from what the tree declares')
    args = ap.parse_args()

    forbidden, fdata = load_forbidden()
    problems: list[str] = []
    warnings: list[str] = []
    inventory: list[dict] = []

    for tdir in sorted(p for p in TASKS.iterdir() if p.is_dir()):
        task = tdir.name
        build, trial = build_text(tdir)
        found = {norm(*m.groups()) for m in URL.finditer(build)}
        remote_trial = trial_fetches_internet(trial)
        if not found and not remote_trial:
            continue
        if remote_trial:
            found |= {norm(*m.groups()) for m in URL.finditer(trial)}

        for repo in sorted(found):
            # 1. disjointness
            if repo in forbidden:
                problems.append(
                    f'{task}: clones {repo}, which the frozen Terminal-Bench 2.1 '
                    f'reference also uses. The two suites must not share an '
                    f'upstream repository; pick a different project of similar '
                    f'scope.')

        # 2. a fetch of an internet host in the trial path cannot work; a URL that
        #    is only fixture data, or a clone of a loopback/local path, is fine
        if remote_trial:
            problems.append(
                f'{task}: runs `{remote_trial}` under tests/ or solution/. The '
                f'trial container has no external network, so this cannot work; '
                f'do it in environment/Dockerfile at build time instead. Cloning '
                f'a loopback or filesystem path is fine and is not what this '
                f'flags.')

        # 3. pinning, per clone command in the build path
        clones = CLONE_LINE.findall(build)
        for line in clones:
            pinned_tag = '--branch' in line or re.search(r'\bclone\b[^\n]*\s-b\s', line)
            shallow = '--depth' in line
            sha = SHA40.search(build)
            if not shallow:
                problems.append(
                    f'{task}: `{" ".join(line.split()[:6])}...` has no --depth. A '
                    f'full history for a large upstream makes the image gigabytes '
                    f'for no benefit.')
            if sha:
                pin = f'sha {sha.group(0)[:12]}'
            elif pinned_tag:
                pin = 'tag only'
                warnings.append(
                    f'{task}: clone is pinned to a tag with no commit assertion. '
                    f'Tags can be force-moved upstream; add '
                    f'`test "$(git rev-parse HEAD)" = <40-hex>` so the build fails '
                    f'closed instead of silently tracking a moved tag.')
            else:
                pin = 'UNPINNED'
                problems.append(
                    f'{task}: `{line.strip()[:90]}` is unpinned. It resolves to a '
                    f'different revision every time upstream moves, so the '
                    f'committed Dockerfile stops reproducing the task that was '
                    f'measured. Pin a tag AND assert the 40-hex commit.')

        inventory.append({
            'task': task,
            'repositories': sorted(found),
            'urls': [f'https://{r}' for r in sorted(found)],
            'clone_commands': len(clones),
            'pinned': bool(SHA40.search(build)),
        })

    if args.apply:
        INVENTORY.write_text(json.dumps({
            'note': 'Upstream source repositories each task clones at image-build '
                    'time, extracted from the build path of every task. Derived; '
                    'regenerate with `python3 tools/check_upstream_disjointness.py '
                    '--apply`. tools/update_provenance.py copies these into '
                    'specs/provenance.json external_sources so '
                    'audit_independence_stream.py --reference-provenance can '
                    'compare them against the reference set.',
            'policy': 'upstream clones are permitted from v4.2 onward provided no '
                      'repository is shared with the frozen Terminal-Bench 2.1 '
                      'reference and every clone is pinned to an immutable '
                      'revision; see specs/tb21_source_repositories.json',
            'forbidden_repository_count': len(forbidden),
            'forbidden_spec_commit': fdata.get('frozen_commit'),
            'task_count': len(inventory),
            'repositories': sorted({r for e in inventory for r in e['repositories']}),
            'tasks': inventory,
        }, indent=1) + '\n')
        print(f'wrote {INVENTORY.relative_to(ROOT)}')

    repos = sorted({r for e in inventory for r in e['repositories']})
    print(f'tasks_cloning_upstream={len(inventory)} distinct_repositories={len(repos)} '
          f'forbidden_list={len(forbidden)} problems={len(problems)} '
          f'warnings={len(warnings)}')
    for w in warnings:
        print('WARN', w)
    for p in problems:
        print('ERROR', p)
    if inventory and args.apply is False and not INVENTORY.exists():
        print('NOTE specs/upstream_sources.json does not exist; run with --apply '
              'once the family is authored so provenance can carry it')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
