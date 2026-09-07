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


def normalise_body(inner: str) -> str:
    """Strip trailing separators so appending the guard cannot make '; ;'.

    A trap body written as 'finalize_reward; ' already ends in a semicolon, and
    appending '; <guard>' to it yields 'finalize_reward; ; <guard>'. Bash rejects
    an empty command between separators, so the trap fails at exit time with a
    syntax error. That is invisible to `bash -n` on the file, because a trap body
    is an ordinary string until the trap actually fires, which is how one shipped
    in v3.3.
    """
    return inner.rstrip().rstrip(';').rstrip()


def trap_bodies(text: str):
    """Yield (line_number, body) for every EXIT trap, for syntax validation."""
    for n, line in enumerate(text.splitlines(), 1):
        m = TRAP_LINE.match(line)
        if not m:
            continue
        body = m.group(2)
        if len(body) >= 2 and body[0] == body[-1] and body[0] in '\'"':
            yield n, body[1:-1]
        else:
            yield n, body


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
            inner = normalise_body(body[1:-1])
            new_body = f"'{inner}; {GUARD}'" if inner else f"'{GUARD}'"
        elif body.startswith('"') and body.endswith('"'):
            return None, 'double-quoted EXIT trap; extend by hand'
        else:
            # trap some_function EXIT
            inner = normalise_body(body)
            new_body = f"'{inner}; {GUARD}'" if inner else f"'{GUARD}'"
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


def repair(text: str):
    """Collapse a doubled separator inside an EXIT trap body.

    Returns (new_text, count). Fixes traps this tool built before it normalised
    the body it was extending.
    """
    n_fixed = 0

    def fix(m):
        nonlocal n_fixed
        indent, body = m.group(1), m.group(2)
        if len(body) >= 2 and body[0] == body[-1] == "'":
            inner = body[1:-1]
            collapsed = re.sub(r';\s*;', ';', inner).strip()
            collapsed = re.sub(r'^(;\s*)+', '', collapsed)
            if collapsed != inner:
                n_fixed += 1
                return f"{indent}trap '{collapsed}' EXIT"
        return m.group(0)

    return TRAP_LINE.sub(fix, text), n_fixed


def trap_parses(text: str):
    """Return [(line, error)] for EXIT trap bodies bash cannot parse.

    `bash -n` on the file does not check these: a trap body is just a string
    until the trap fires, so a malformed one is discovered at exit time, after
    the verdict was already lost.
    """
    import subprocess
    problems = []
    for n, body in trap_bodies(text):
        if not body.strip():
            continue
        r = subprocess.run(['bash', '-n', '-c', body],
                           capture_output=True, text=True)
        if r.returncode != 0:
            problems.append((n, r.stderr.strip().splitlines()[-1] if r.stderr.strip()
                             else 'unparseable'))
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()

    patched, already, skipped = [], 0, []
    repaired, unparseable = [], []
    for d in sorted(TASKS.iterdir()):
        ts = d / 'tests' / 'test.sh'
        if not ts.is_file():
            continue
        text = ts.read_text(errors='replace')
        # Fix traps this tool previously broke before deciding anything else.
        fixed_text, n_fixed = repair(text)
        if n_fixed:
            repaired.append((d.name, n_fixed))
            text = fixed_text
            if args.apply:
                ts.write_text(text)
        bad = trap_parses(text)
        if bad:
            unparseable.append((d.name, bad))
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
    if repaired:
        print(f'repaired broken EXIT traps: {len(repaired)}')
        for name, n in repaired:
            print(f'  {name}: {n}')
    if unparseable:
        print(f'EXIT TRAP BODIES BASH CANNOT PARSE: {len(unparseable)}')
        for name, bad in unparseable:
            for line, err in bad:
                print(f'  {name} line {line}: {err}')
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
    # pipeline stays green. An EXIT trap bash cannot parse is the same defect by
    # another route: the safety net is there in the file and absent at exit time.
    return 1 if (skipped or unparseable or (patched and not args.apply)
                 or (repaired and not args.apply)) else 0


if __name__ == '__main__':
    sys.exit(main())
