#!/usr/bin/env python3
"""Pin every pip dependency a task image installs.

Half the suite installed floating package versions. `RUN pip install numpy` in a
task Dockerfile resolves to whatever PyPI serves that day, so the same committed
Dockerfile builds a different environment over time and a task's difficulty, or
whether its verifier passes at all, can change with no edit to the repository.
228 tasks did this across 89 packages; numpy alone floated in 111 of them.

This is not hypothetical. tasks/amber-dial's Dockerfile carried the comment "torch
is pulled as the CPU build (default wheel on this base)" while `pip install torch`
actually resolved to 2.13.0+cu130, a CUDA build. That mismatch was load-bearing:
the CUDA torch picks its intra-op thread count from the host core count, which is
what produced the 325x slowdown against a one-CPU quota that made the task's own
reference solution exceed the verifier's budget.

Versions are resolved with the base image's own interpreter and the index the task
actually names, so a pin records what that environment would install rather than
what PyPI's global latest happens to be. That distinction matters: the pytorch CPU
index serves different builds than PyPI, and bench-base:node-22 carries Python
3.11 while bench-base:python-3.12 carries 3.12.

apt packages are deliberately NOT pinned here. Debian and Ubuntu rotate their
archives, so `apt-get install gcc=4:13.2.0-1` stops resolving once that version is
published out, which would convert silent drift into a hard build failure across
209 tasks. Reproducible apt needs a snapshot mirror or vendored .debs; see
specs/pinned_python_deps.json for what is recorded instead.

Usage:
  python3 tools/pin_python_dependencies.py             # gate: report drift
  python3 tools/pin_python_dependencies.py --apply     # rewrite Dockerfiles
  python3 tools/pin_python_dependencies.py --resolve   # re-query the indexes
"""
from __future__ import annotations

import argparse
import collections
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'
SPEC = ROOT / 'specs' / 'pinned_python_deps.json'

BASE_RE = re.compile(r'^\s*FROM\s+(\S+)', re.M)
# a pip install command, up to whatever ends it
PIP_RE = re.compile(r'\bpip3?\s+install\b')
NAME_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.\-]*(\[[A-Za-z0-9_,.\-]+\])?$')


def dockerfiles():
    for t in sorted(os.listdir(TASKS)):
        p = TASKS / t / 'environment' / 'Dockerfile'
        if p.is_file():
            yield t, p


def base_of(text: str):
    bases = [m.group(1) for m in BASE_RE.finditer(text)]
    return bases[-1] if bases else None


def command_span(text: str, start: int):
    """End offset of the pip install command that begins at `start`.

    Follows backslash line continuations and stops at a shell operator, since a
    Dockerfile RUN is one shell command line even when it is written across many.
    """
    i = start
    n = len(text)
    while i < n:
        c = text[i]
        if c == '\\' and i + 1 < n and text[i + 1] == '\n':
            i += 2
            continue
        if c == '\n':
            return i
        if text.startswith('&&', i) or text.startswith('||', i) or c == ';':
            return i
        i += 1
    return n


def is_comment_line(text: str, pos: int) -> bool:
    ls = text.rfind('\n', 0, pos) + 1
    return text[ls:pos].strip().startswith('#')


def install_sites(text: str):
    """Yield (span_start, span_end, index_url) for each real pip install."""
    for m in PIP_RE.finditer(text):
        if is_comment_line(text, m.start()):
            continue
        end = command_span(text, m.end())
        idx = None
        args = split_args(text[m.end():end])
        for i, (_, a) in enumerate(args):
            if a in ('--index-url', '-i') and i + 1 < len(args):
                idx = args[i + 1][1]
            elif a.startswith('--index-url='):
                idx = a.split('=', 1)[1]
        yield m.end(), end, (idx or 'pypi')


# Options that consume the following token as a value. Without this the walker
# reads the URL in `--index-url https://download.pytorch.org/whl/cpu` as a package
# name, which is how 'https' and stray digits ended up in the requirement list.
VALUE_OPTS = {
    '-i', '--index-url', '--extra-index-url', '-f', '--find-links', '-c',
    '--constraint', '-t', '--target', '--prefix', '--src', '-b', '--build',
    '--cache-dir', '--python', '--root', '--platform', '--python-version',
    '--implementation', '--abi', '-e', '--editable', '-r', '--requirement',
    '--config-settings', '--global-option', '--install-option', '--hash',
    '--dist-info-dir', '--no-python-version-warning',
}


def split_args(span: str):
    """Split an install command into (offset, token) pairs, unwrapping quotes.

    The offset points at the requirement text itself, not at an opening quote, so
    a caller rewriting in place replaces the name and leaves the quotes where they
    were. `'moto[server]'` is a real requirement and used to be skipped whole
    because the quoted form did not match the name pattern.
    """
    out = []
    i = 0
    n = len(span)
    while i < n:
        while i < n and span[i].isspace():
            i += 1
        if i >= n:
            break
        start = i
        body_start = i
        quote = None
        if span[i] in '"\'':
            quote = span[i]
            i += 1
            body_start = i
        while i < n:
            c = span[i]
            if quote:
                if c == quote:
                    quote = None
                    i += 1
                    break
            elif c.isspace():
                break
            i += 1
        body_end = i - 1 if (i > body_start and span[i - 1] in '"\'') else i
        out.append((body_start, span[body_start:body_end]))
        _ = start
    return out


def is_requirement(tok: str) -> bool:
    """True when a token is a bare package requirement we can pin."""
    if not tok or tok.startswith('-'):
        return False
    if '://' in tok or tok.startswith('/') or tok.startswith('.'):
        return False
    if tok.endswith(('.whl', '.tar.gz', '.zip', '.tgz')):
        return False
    if any(ch in tok for ch in '=<>!~@'):
        return False          # already pinned, a VCS URL, or an option value
    if tok[0].isdigit() and not re.match(r'^[A-Za-z0-9]', tok):
        return False
    if re.fullmatch(r'[0-9.]+', tok):
        return False          # a stray number, not a distribution name
    return bool(NAME_RE.fullmatch(tok))


def tokens(span: str):
    """Yield (offset, length, name, extras) for each bare requirement in a span."""
    args = split_args(span)
    skip_next = False
    for off, tok in args:
        if skip_next:
            skip_next = False
            continue
        if tok in VALUE_OPTS:
            skip_next = True
            continue
        if tok.startswith('-') and '=' in tok:
            continue          # --opt=value
        if tok.startswith('-'):
            continue          # a flag
        if not is_requirement(tok):
            continue
        m = re.match(r'^([A-Za-z0-9][A-Za-z0-9_.\-]*)(\[[^\]]*\])?$', tok)
        if not m:
            continue
        name, extras = m.group(1), (m.group(2) or '')
        if name.endswith('.'):
            continue
        # The replaced run covers the extras too, so 'moto[server]' becomes
        # 'moto[server]==5.2.3' rather than 'moto[server]==5.2.3[server]'.
        yield off, len(name) + len(extras), name, extras


def load_spec():
    if not SPEC.is_file():
        return {}
    return json.loads(SPEC.read_text())


def resolve(sites):
    """Ask each base image's own pip what it would install, per index."""
    combos = collections.defaultdict(set)
    for task, path, base, idx, names in sites:
        for n in names:
            combos[(base, idx)].add(n)
    out = {}
    for (base, idx), pkgs in sorted(combos.items()):
        pkgs = sorted(pkgs)
        iu = ('--index-url %s ' % idx) if idx != 'pypi' else ''
        # ubuntu/node bases do not always ship pip, so install it first if needed
        script = ('command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1 || '
                  '{ apt-get update -qq >/dev/null 2>&1; '
                  'apt-get install -y -qq --no-install-recommends python3-pip >/dev/null 2>&1; }; '
                  'python3 -m pip install --break-system-packages --dry-run '
                  '--ignore-installed --no-deps %s--report /tmp/r.json %s >/dev/null 2>&1 || '
                  'python3 -m pip install --dry-run --ignore-installed --no-deps '
                  '%s--report /tmp/r.json %s >/dev/null 2>&1; cat /tmp/r.json'
                  % (iu, ' '.join(pkgs), iu, ' '.join(pkgs)))
        print('resolving %2d package(s) on %-26s %s' % (len(pkgs), base, idx), flush=True)
        p = subprocess.run(['docker', 'run', '--rm', '--entrypoint', 'sh', base, '-c', script],
                           capture_output=True, text=True, timeout=3600)
        raw = p.stdout
        i = raw.find('{')
        if i < 0:
            print('  FAILED: %s' % (p.stderr or raw)[-200:].strip())
            continue
        try:
            d = json.loads(raw[i:])
        except ValueError as e:
            print('  FAILED to parse report: %s' % e)
            continue
        got = {it['metadata']['name'].lower(): it['metadata']['version']
               for it in d.get('install', [])}
        out['%s|%s' % (base, idx)] = got
        print('  -> %d version(s)' % len(got))
    return out


def collect_sites():
    """Every unpinned requirement in every task Dockerfile."""
    sites = []
    for task, path in dockerfiles():
        text = path.read_text(errors='replace')
        base = base_of(text)
        for start, end, idx in install_sites(text):
            span = text[start:end]
            names = [n for _, _, n, _ in tokens(span)]
            if names:
                sites.append((task, path, base, idx, names))
    return sites


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true',
                    help='rewrite task Dockerfiles with the pinned versions')
    ap.add_argument('--resolve', action='store_true',
                    help='re-query the indexes and rewrite the spec')
    args = ap.parse_args()

    sites = collect_sites()
    spec = load_spec()

    if args.resolve:
        versions = resolve(sites)
        spec = {
            'note': ('Versions each base image\'s own pip resolves for the packages '
                     'task Dockerfiles install, keyed "<base>|<index>". Resolved with '
                     '--dry-run --ignore-installed --no-deps so nothing is installed, '
                     'against the index the task names rather than PyPI globally, '
                     'because the pytorch CPU index serves different builds and the '
                     'bases carry different Pythons (3.11 on bench-base:node-22, '
                     '3.12 on bench-base:python-3.12).'),
            'apt_note': ('apt packages are not pinned. Debian and Ubuntu rotate their '
                         'archives, so an exact version pin stops resolving once that '
                         'version is published out and turns silent drift into a hard '
                         'build failure. Reproducible apt needs a snapshot mirror or '
                         'vendored .debs.'),
            'resolved_at': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
            'versions': versions,
        }
        SPEC.write_text(json.dumps(spec, indent=1) + '\n')
        print('wrote %s' % SPEC)

    versions = (spec or {}).get('versions', {})
    if not versions:
        print('FATAL: no pinned versions recorded; run with --resolve first',
              file=sys.stderr)
        return 2

    rewritten, unpinned, unknown, mismatched = [], [], [], []
    for task, path, base, idx, names in sites:
        text = path.read_text(errors='replace')
        table = versions.get('%s|%s' % (base, idx), {})
        out = []
        cursor = 0
        changed = False
        for start, end, sidx in install_sites(text):
            stable = versions.get('%s|%s' % (base, sidx), {})
            span = text[start:end]
            pieces = []
            last = 0
            for off, length, name, extras in tokens(span):
                ver = stable.get(name.lower())
                if ver is None:
                    unknown.append((task, name, base, sidx))
                    continue
                pieces.append(span[last:off])
                pieces.append('%s%s==%s' % (name, extras, ver))
                last = off + length
                changed = True
            pieces.append(span[last:])
            out.append(text[cursor:start])
            out.append(''.join(pieces))
            cursor = end
        out.append(text[cursor:])
        if changed:
            new = ''.join(out)
            if new != text:
                rewritten.append(task)
                if args.apply:
                    path.write_text(new)

    # gate: after applying, nothing may remain unpinned
    if args.apply:
        left = []
        for task, path, base, idx, names in collect_sites():
            table = versions.get('%s|%s' % (base, idx), {})
            for n in names:
                if n.lower() not in table:
                    left.append((task, n))
        print('rewrote %d Dockerfiles' % len(rewritten))
        if left:
            print('STILL UNPINNED (no resolved version recorded): %d' % len(left))
            for t, n in sorted(set(left))[:20]:
                print('  %-24s %s' % (t, n))
            return 1
        return 0

    print('pip install sites: %d across %d tasks' % (len(sites), len({s[0] for s in sites})))
    print('Dockerfiles that would be pinned: %d' % len(rewritten))
    if unknown:
        print('requirements with no resolved version: %d' % len(set(unknown)))
        for t, n, b, i in sorted(set(unknown))[:20]:
            print('  %-24s %-20s %s|%s' % (t, n, b, i))
    by = collections.Counter()
    for _, _, base, idx, names in sites:
        by[base] += len(names)
    for b, n in by.most_common():
        print('  %-26s %d unpinned requirements' % (b, n))
    if rewritten or unknown:
        print('\nrun with --resolve then --apply')
        return 1
    print('every pip requirement is pinned to a recorded version')
    return 0


if __name__ == '__main__':
    sys.exit(main())
