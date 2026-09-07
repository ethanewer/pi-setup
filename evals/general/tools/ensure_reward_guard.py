#!/usr/bin/env python3
"""Guarantee every verifier writes a reward, whatever happens.

A verifier that exits without writing /logs/verifier/reward.txt produces a record
that cannot be scored. That is not hypothetical: cedar-canyon imports the agent's
/app/solve.py and calls solve.binding_prefix, and a submission that lacked that
attribute killed the verifier with AttributeError before it reached either reward
write. The trial finished, harbor raised RewardFileNotFoundError, and the record
went to the dataset with no reward. Four of the 22 unscoreable records v3.2
published were that shape rather than an agent timeout.

705 of 787 verifiers had no guard against it, and 360 of those run a python
heredoc that inspects agent-authored code and can raise on an unexpected shape.
Only 82 protected themselves, using a pattern the suite already had:

    trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT

This applies that pattern everywhere. The guard fires only when no reward was
written, so it cannot change a verdict a verifier actually reached; it converts
"no verdict" into "0 plus a loud diagnostic", which is the correct reading, since
a verifier that cannot grade the deliverable has not passed it.

An existing EXIT trap is extended rather than replaced, so cleanup handlers that
kill a server or restore a file keep running.

Usage:
  python3 tools/ensure_reward_guard.py            # report only
  python3 tools/ensure_reward_guard.py --apply    # patch
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'
REWARD = '/logs/verifier/reward.txt'

# No single quotes, so this is safe inside a single-quoted trap body.
GUARD = ('[ -f ' + REWARD + ' ] || { echo "VERIFIER EXITED WITHOUT WRITING A '
         'REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > ' + REWARD + '; }')

# a verifier that already guarantees a reward on every path
ALREADY = [
    re.compile(r'trap\s+[^\n]*reward\.txt'),
    re.compile(r'if\s+\[\s*!\s+-[fs]\s+\S*reward\.txt\s*\]'),
    re.compile(r'except[^\n]*:\s*\n[^\n]*reward\.txt'),
    re.compile(r'finally\s*:'),
    re.compile(r'atexit'),
]
TRAP_LINE = re.compile(r'^(\s*)trap\s+(.*?)\s+EXIT\s*$', re.M)


def has_guard(text: str) -> bool:
    return any(g.search(text) for g in ALREADY)


def insertion_point(lines):
    """Index just past the shebang and the leading comment block."""
    i = 0
    if lines and lines[0].startswith('#!'):
        i = 1
    while i < len(lines):
        s = lines[i].strip()
        if s == '' or s.startswith('#'):
            i += 1
            continue
        break
    return i


def patch(text: str):
    """Return (new_text, how) or (None, reason) when it cannot be patched."""
    m = TRAP_LINE.search(text)
    if m:
        indent, body = m.group(1), m.group(2)
        if body.startswith("'") and body.endswith("'") and body.count("'") == 2:
            inner = body[1:-1]
            new_body = f"'{inner}; {GUARD}'"
        elif body.startswith('"') and body.endswith('"'):
            return None, 'double-quoted EXIT trap; extend by hand'
        else:
            # trap some_function EXIT
            new_body = f"'{body}; {GUARD}'"
        new = text[:m.start()] + f'{indent}trap {new_body} EXIT' + text[m.end():]
        return new, 'extended existing EXIT trap'

    lines = text.splitlines(keepends=True)
    at = insertion_point(lines)
    block = [f"# Guarantee a reward on every exit path. Without this a verifier that\n",
             f"# raises while inspecting the agent's deliverable writes nothing at all,\n",
             f"# which yields a record that cannot be scored.\n",
             f"trap '{GUARD}' EXIT\n"]
    if at < len(lines) and lines[at].strip() != '':
        block.append('\n')
    return ''.join(lines[:at] + block + lines[at:]), 'inserted EXIT trap'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()

    patched, already, skipped = [], 0, []
    for d in sorted(TASKS.iterdir()):
        ts = d / 'tests' / 'test.sh'
        if not ts.is_file():
            continue
        text = ts.read_text(errors='replace')
        if 'reward.txt' not in text:
            skipped.append((d.name, 'never writes reward.txt'))
            continue
        if has_guard(text):
            already += 1
            continue
        new, how = patch(text)
        if new is None:
            skipped.append((d.name, how))
            continue
        patched.append((d.name, how))
        if args.apply:
            ts.write_text(new)

    verb = 'patched' if args.apply else 'would patch'
    print(f'{verb}: {len(patched)}   already guarded: {already}   '
          f'skipped: {len(skipped)}')
    kinds = {}
    for _, how in patched:
        kinds[how] = kinds.get(how, 0) + 1
    for k, v in sorted(kinds.items()):
        print(f'  {k}: {v}')
    for name, why in skipped:
        print(f'  SKIP {name}: {why}')
    if patched and not args.apply:
        print(f'\n{len(patched)} verifiers can still exit without writing a '
              f'reward; re-run with --apply')
    # As a gate this must fail whenever any verifier is unguarded or unpatchable,
    # otherwise a new task can reintroduce the unscoreable-record defect and the
    # pipeline stays green.
    return 1 if (skipped or (patched and not args.apply)) else 0


if __name__ == '__main__':
    sys.exit(main())
