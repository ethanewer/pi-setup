#!/usr/bin/env python3
"""Image-size hygiene gate for tasks that build real upstream projects.

The v4.3 waves put agents inside real repositories, which means real toolchains
and real build artifacts in the image. Two of them grew past 20 GB and one past
30 GB. That is not inherent to the work; it is two specific Dockerfile habits, and
both are avoidable.

**Ownership changes in their own RUN layer.** Docker layers are copy-on-write, so
`RUN chown -R 1000:1000 /app/src` after a `RUN make` that filled /app/src writes a
second copy of every file the chown touched into a new layer. Measured here on a
400 MB blob: the image went from 1.07 GB to 1.49 GB, exactly the blob size. In
tasks/gunwale-tideway the pattern appears as two layers of exactly 2.74 GB each,
because line 38 builds git with `make -j1` and line 58 chowns the tree in a
separate RUN. Half of that 6.73 GB image is the same bytes twice.

The fix is to make the ownership correct when the files are created rather than
correcting it afterwards: create the directory as the target user, use
`COPY --chown=`, or put the chown in the SAME `RUN` as the build that produced the
files. A chown in the same layer as the creation costs nothing extra, because the
layer is written once.

**Retained build artifacts the trial does not need.** A Rust `target/` directory,
a Gradle or Maven cache, `node_modules/.cache`, and `__pycache__` trees are build
byproducts. If the agent does not need to relink incrementally, delete them at the
end of the RUN that created them. If it does need incremental relinking, keep them
but never chown them in a later layer.

Budget: aim under 6 GB, hard limit 12 GB. For scale, the largest image in the v4.2
upstream-clone wave was 3.7 GB (angr), and a task that needs more than 12 GB is
not distributable even though it passes its own gates -- `storage_mb` is advisory
in harbor 0.22.0 and is never passed to docker as a limit, so nothing else will
catch it.

This gate is static: it reads Dockerfiles and does not build anything, so it runs
in seconds over the whole suite. It reports the measured size of any image that
happens to be present locally, but does not require one.

Usage:
  python3 tools/check_image_size_hygiene.py            # gate
  python3 tools/check_image_size_hygiene.py --verbose  # include advisories
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'

SOFT_GB = 6.0
HARD_GB = 12.0

# `chown -R` / `chmod -R` on a path, in a RUN of its own.
OWN_RUN = re.compile(
    r'^\s*RUN\s+(?:[^#\n]*?\b)(chown|chmod)\s+-R\b[^\n]*', re.M)
# A RUN that plausibly fills a tree: a build, a clone, an install, an extract.
FILLS = re.compile(
    r'\b(make|cmake|ninja|meson|cargo build|cargo install|go build|mvn|gradle|'
    r'git clone|git checkout|pip install|npm (install|ci)|yarn|tar |unzip |'
    r'rustup|./configure)\b')
# Only a COMPILE step produces gigabytes of byproduct. Duplicating a cloned
# source tree costs tens of megabytes and is not worth failing a task over;
# duplicating a `make` or `cargo build` output directory costs gigabytes. The
# distinction is what keeps this gate pointed at real waste instead of firing on
# all 129 ownership changes in the suite.
FILLS_BUILD = re.compile(
    r'\b(make(?:\s+-j\d*)?|cmake|ninja|meson(?:\s+setup|\s+compile)?|'
    r'cargo\s+(?:build|install|test)|go\s+build|mvn|gradle|./configure|'
    r'autoreconf|makepkg)\b')
# Artifact directories that are pure build byproduct.
ARTIFACTS = re.compile(
    r'(^|/)(target|build|dist|node_modules/\.cache|\.gradle|\.m2/repository|'
    r'__pycache__|\.cargo/registry/cache)($|/)')
RUSTUP_FULL = re.compile(r'rustup\s+toolchain\s+install(?![^\n]*--profile\s+minimal)')


def split_runs(dockerfile: str) -> list[str]:
    """Split a Dockerfile into RUN instructions, honouring line continuations."""
    runs, cur, in_run = [], [], False
    for line in dockerfile.splitlines():
        s = line.strip()
        if s.startswith('RUN '):
            in_run = True
            cur = [s[4:]]
        elif in_run:
            cur.append(s)
        if in_run and not s.endswith('\\'):
            runs.append(' '.join(cur))
            in_run, cur = False, []
    if cur:
        runs.append(' '.join(cur))
    return runs


def image_size_gb(tag: str) -> float | None:
    try:
        out = subprocess.run(['docker', 'images', '--format', '{{.Size}}', tag],
                             capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception:
        return None
    if not out:
        return None
    m = re.match(r'([\d.]+)(GB|MB|KB)', out.splitlines()[0])
    if not m:
        return None
    v = float(m.group(1))
    return v if m.group(2) == 'GB' else v / 1024


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    problems: list[str] = []
    advisories: list[str] = []
    measured: list[tuple[str, float]] = []
    scanned = 0

    for tdir in sorted(p for p in TASKS.iterdir() if p.is_dir()):
        df = tdir / 'environment' / 'Dockerfile'
        if not df.exists():
            continue
        scanned += 1
        name = tdir.name
        text = df.read_text(errors='replace')
        runs = split_runs(text)

        # Which RUNs fill a tree, and which paths do they touch? Separate the
        # paths a compiler filled from the paths a clone or install filled, so
        # only the expensive duplication is an error.
        filled: set[str] = set()
        built: set[str] = set()
        for r in runs:
            hit_fill = bool(FILLS.search(r))
            hit_build = bool(FILLS_BUILD.search(r))
            if not (hit_fill or hit_build):
                continue
            for m in re.finditer(r'(/(?:app|opt|usr/local|work|tmp)/[\w./\-+]*)', r):
                p = m.group(1).rstrip('/')
                if hit_fill:
                    filled.add(p)
                if hit_build:
                    built.add(p)

        for r in runs:
            m = re.match(r'\s*(chown|chmod)\s+-R\b(.*)$', r.strip())
            if not m:
                continue
            targets = re.findall(r'(/[\w./\-+]+)', m.group(2))
            for tgt in targets:
                tgt = tgt.rstrip('/')
                overlaps = lambda s: any(
                    tgt == f or tgt.startswith(f + '/') or f.startswith(tgt + '/')
                    for f in s)
                if overlaps(built):
                    problems.append(
                        f'{name}: `{m.group(1)} -R` on {tgt} in its own RUN layer '
                        f'duplicates a tree an earlier RUN compiled into. Docker '
                        f'layers are copy-on-write, so every object file is stored '
                        f'twice; in tasks/gunwale-tideway this pattern shows up as '
                        f'two layers of exactly 2.74 GB. Move the {m.group(1)} into '
                        f'the same RUN as the build, create the tree as uid 1000 in '
                        f'the first place, or run the build as that user.')
                    break
                if overlaps(filled):
                    advisories.append(
                        f'{name}: `{m.group(1)} -R` on {tgt} in its own RUN layer '
                        f'duplicates a cloned or installed tree. Cheap here, but '
                        f'free if folded into the RUN that created it.')
                    break

        if RUSTUP_FULL.search(text):
            advisories.append(
                f'{name}: rustup toolchain install without --profile minimal pulls '
                f'docs, clippy and rustfmt the task probably does not use')

        for m in ARTIFACTS.finditer(text):
            pass  # reported only if also chowned; too noisy on its own

        size = image_size_gb(f'{name}:latest')
        if size is None:
            # harbor's own trial tag, if this task has been run here
            try:
                out = subprocess.run(
                    ['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}\t{{.Size}}'],
                    capture_output=True, text=True, timeout=60).stdout
                for line in out.splitlines():
                    if line.startswith(f'{name}__') and '__env-main' in line:
                        rt, sz = line.split('\t')
                        v = float(re.match(r'([\d.]+)', sz).group(1))
                        size = v if sz.endswith('GB') else v / 1024
                        break
            except Exception:
                pass
        if size is not None:
            measured.append((name, size))
            if size > HARD_GB:
                problems.append(
                    f'{name}: built image is {size:.1f} GB, over the {HARD_GB:.0f} GB '
                    f'hard limit. Nothing else catches this: storage_mb is advisory '
                    f'in harbor 0.22.0 and is never passed to docker as a limit.')
            elif size > SOFT_GB:
                advisories.append(
                    f'{name}: built image is {size:.1f} GB, over the {SOFT_GB:.0f} GB '
                    f'budget')

    print(f'dockerfiles_scanned={scanned} problems={len(problems)} '
          f'advisories={len(advisories)} images_measured={len(measured)}')
    if measured:
        measured.sort(key=lambda x: -x[1])
        print(f'largest measured images: ' +
              ', '.join(f'{n} {s:.1f}GB' for n, s in measured[:5]))
    if args.verbose:
        for a in advisories:
            print('WARN', a)
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
