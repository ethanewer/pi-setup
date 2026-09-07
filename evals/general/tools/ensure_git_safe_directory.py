#!/usr/bin/env python3
"""Mark git repositories safe for every user in images that build one.

Git refuses to operate on a repository owned by someone other than the current
user, and exits 128 with "detected dubious ownership". Eight tasks in this suite
build a repository at image-build time, which runs as root, so the repository is
root-owned. Whether the trial then works depends entirely on which user the
harness runs it as: as root, `git reflog --all` succeeds; as uid 1000 the same
command dies. v1-skill-dangling-commits passed the pre-repair oracle census and
failed the post-repair one with no change to the task in between, which is what
made the flake visible -- its oracle runs under `set -euo pipefail`, so git's 128
propagated out of a pipeline and the whole solution aborted.

The fix is a system-wide safe.directory entry, written to /etc/gitconfig rather
than root's ~/.gitconfig so it applies to whichever user the trial runs as. The
value is the wildcard rather than a per-task path because the repositories differ
(/app/repo, /app/repo.git, /app/workflow, /home/sshgit/repos/team.git, and some
are created with `git init .` inside a WORKDIR) and because agents routinely clone
into directories of their own, which a fixed path would not cover. The ownership
check protects a long-lived multi-user machine; it protects nothing in a
single-task container that is discarded after one trial.

Usage:
  python3 tools/ensure_git_safe_directory.py            # report only
  python3 tools/ensure_git_safe_directory.py --apply    # patch
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'

# A Dockerfile that creates a repository at build time.
CREATES_REPO = re.compile(r'\bgit\s+(init|clone)\b')
ALREADY = re.compile(r'safe\.directory')

RUN_LINE = re.compile(r'^\s*RUN\s+', re.I | re.M)

BLOCK = (
    '\n# The repository below is created by this RUN, so it is root-owned, and git\n'
    '# refuses to operate on a repository owned by another user: it exits 128 with\n'
    '# "detected dubious ownership". Whether the trial works then depends on which\n'
    '# user the harness runs it as. Record the exception in /etc/gitconfig rather\n'
    '# than root\'s ~/.gitconfig so it holds for every user, and use the wildcard\n'
    '# because agents also clone into directories of their own.\n'
    'RUN git config --system --add safe.directory \'*\'\n')


def patch(text: str):
    """Insert the safe.directory RUN before the first RUN that creates a repo."""
    m = CREATES_REPO.search(text)
    if not m:
        return None
    # anchor on the RUN instruction that contains it, so the config is in place
    # before the repository is built and in the same layer ordering
    starts = [rm.start() for rm in RUN_LINE.finditer(text) if rm.start() < m.start()]
    at = starts[-1] if starts else None
    if at is None:
        # the repo is created outside a RUN (unlikely); append after the last FROM
        fm = list(re.finditer(r'^\s*FROM\s+.*$', text, re.I | re.M))
        if not fm:
            return None
        at = fm[-1].end()
        nl = text.find('\n', at)
        at = nl + 1 if nl >= 0 else len(text)
        return text[:at] + BLOCK + text[at:]
    return text[:at] + BLOCK.lstrip('\n') + text[at:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()

    patched, done, skipped = [], [], []
    for t in sorted(os.listdir(TASKS)):
        dock = TASKS / t / 'environment' / 'Dockerfile'
        if not dock.is_file():
            continue
        text = dock.read_text(errors='replace')
        if not CREATES_REPO.search(text):
            continue
        if ALREADY.search(text):
            done.append(t)
            continue
        new = patch(text)
        if new is None:
            skipped.append((t, 'could not find an anchor for the RUN'))
            continue
        patched.append(t)
        if args.apply:
            dock.write_text(new)

    verb = 'patched' if args.apply else 'would patch'
    print('%s: %d   already safe: %d   skipped: %d'
          % (verb, len(patched), len(done), len(skipped)))
    for t in patched:
        print('  %s' % t)
    for t, why in skipped:
        print('  SKIP %s: %s' % (t, why))
    if patched and not args.apply:
        print('\n%d images build a root-owned repository without a safe.directory '
              'entry, so their trials fail or pass on whichever user the harness '
              'picks; re-run with --apply' % len(patched))
    return 1 if (skipped or (patched and not args.apply)) else 0


if __name__ == '__main__':
    sys.exit(main())
