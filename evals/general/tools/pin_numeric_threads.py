#!/usr/bin/env python3
"""Pin numeric thread pools to the CPU budget a task declares.

task.toml's [environment] cpus is enforced by Docker as a CFS quota, not as a
CPU-affinity mask. The process therefore still sees every host core, and every
thread pool that sizes itself from the core count asks for far more threads than
the quota can schedule. On this 64-core host a task declaring cpus = 1 gets 32
OpenMP/intra-op threads fighting over one CPU's worth of runtime.

That is not a rounding error. Measured in tasks/amber-dial's own image with its
own reference solution, 320 training steps took 519.8s against 1.6s once the
pools were pinned to one thread: a 325x penalty. The verifier allows 180s per
invocation, so the reference solution could not pass, and neither could any agent
that wrote an ordinary torch training loop. tasks/brine-mesa shows the same thing
from the other direction -- it requires its OpenMP build to beat its serial
build, and 64 threads on a 4-CPU quota made parallel 5.6x SLOWER than serial
(20.040s against 3.594s), so the required speedup was unreachable.

The fix belongs in the environment rather than in any one solution: a container
that declares a CPU budget should also declare the matching thread count. This
sets OMP_NUM_THREADS and the equivalent variables for MKL, OpenBLAS and numexpr
to the declared cpus, which is what each pool would have chosen had it been able
to see the quota.

Pinning only removes oversubscription. It cannot change a computed result, so a
verdict already reached stays reached; what it changes is whether a correct
solution finishes inside its budget at all.

Usage:
  python3 tools/pin_numeric_threads.py            # report only
  python3 tools/pin_numeric_threads.py --apply    # patch
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _toml_compat import loads  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'

# Libraries whose thread pools size themselves from the host core count.
THREADED_LIBS = re.compile(
    r'\b(torch|tensorflow|jax|scipy|scikit-learn|pyspark|numpy|openblas|mkl)\b')
# Native OpenMP, which reads OMP_NUM_THREADS the same way.
OPENMP = re.compile(r'-fopenmp|\bomp\.h\b|libomp', re.I)

# The variables that cover the pools in use across this suite. OMP_NUM_THREADS is
# read by OpenMP itself and by torch's intra-op pool; the rest cover the BLAS and
# expression-evaluator backends numpy and scipy pick up.
VARS = ('OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
        'NUMEXPR_NUM_THREADS')

# Uppercase and anchored, and never matched inside a RUN heredoc. The original
# form was `^\s*FROM\s+` with re.I, which matched the `from transformers import
# ...` line inside opal-basin's `RUN python3 - <<'PY'` block and injected the ENV
# instruction into the middle of that Python source, so the image no longer built.
FROM_LINE = re.compile(r'^FROM\s+', re.M)
HEREDOC_START = re.compile(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?\s*$")


def heredoc_regions(text: str):
    """Line ranges covered by a RUN heredoc, as (first, last) inclusive 1-based."""
    regions = []
    tag = None
    start = 0
    for n, line in enumerate(text.splitlines(), 1):
        if tag is None:
            m = HEREDOC_START.search(line.rstrip())
            if m and '<<' in line:
                tag, start = m.group(1), n
        elif line.strip() == tag:
            regions.append((start, n))
            tag = None
    return regions


def _in_heredoc(regions, lineno: int) -> bool:
    return any(a <= lineno <= b for a, b in regions)


def threaded(task_dir: Path, dockerfile: str) -> str | None:
    """Why this task is thread-sensitive, or None."""
    if THREADED_LIBS.search(dockerfile):
        hits = sorted(set(THREADED_LIBS.findall(dockerfile)))
        return 'installs ' + ', '.join(hits)
    # the toolchain may live in the image while the OpenMP code lives in the task
    for rel in ('solution', 'tests', 'environment'):
        d = task_dir / rel
        if not d.is_dir():
            continue
        for p in d.rglob('*'):
            if not p.is_file() or p.stat().st_size > 400_000:
                continue
            try:
                if OPENMP.search(p.read_text(errors='replace')):
                    return 'builds OpenMP code (%s)' % p.name
            except OSError:
                continue
    return None


def already_pinned(dockerfile: str) -> bool:
    return 'OMP_NUM_THREADS' in dockerfile


def patch(dockerfile: str, cpus: int):
    """Insert the ENV after the last real FROM, so it applies to the stage that runs."""
    body = ' \\\n'.join(
        ['%s=%d' % (VARS[0], cpus)]
        + ['    %s=%d' % (v, cpus) for v in VARS[1:]])
    block = (
        '\n# [environment] declares cpus = %d, which Docker enforces as a CFS\n'
        '# quota and not as a CPU-affinity mask: the process still sees every\n'
        '# host core, so thread pools sized from the core count oversubscribe the\n'
        '# quota badly. Pin them to the declared budget.\n'
        'ENV %s\n' % (cpus, body))
    regions = heredoc_regions(dockerfile)
    starts = []
    for m in FROM_LINE.finditer(dockerfile):
        lineno = dockerfile.count('\n', 0, m.start()) + 1
        if not _in_heredoc(regions, lineno):
            starts.append(m.end())
    if not starts:
        return None
    at = dockerfile.find('\n', starts[-1])
    if at < 0:
        return dockerfile + block
    return dockerfile[:at + 1] + block + dockerfile[at + 1:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()

    pinned, done, skipped = [], [], []
    for t in sorted(os.listdir(TASKS)):
        td = TASKS / t
        toml, dock = td / 'task.toml', td / 'environment' / 'Dockerfile'
        if not toml.is_file() or not dock.is_file():
            continue
        try:
            meta = loads(toml.read_text())
        except Exception as exc:
            skipped.append((t, 'task.toml unreadable: %s' % exc))
            continue
        cpus = (meta.get('environment') or {}).get('cpus')
        if not isinstance(cpus, int) or cpus < 1:
            continue
        text = dock.read_text(errors='replace')
        why = threaded(td, text)
        if not why:
            continue
        if already_pinned(text):
            done.append((t, cpus))
            continue
        new = patch(text, cpus)
        if new is None:
            skipped.append((t, 'no FROM line to anchor the ENV'))
            continue
        pinned.append((t, cpus, why))
        if args.apply:
            dock.write_text(new)

    verb = 'pinned' if args.apply else 'would pin'
    print('%s: %d   already pinned: %d   skipped: %d'
          % (verb, len(pinned), len(done), len(skipped)))
    budgets: dict[int, int] = {}
    for _, cpus, _ in pinned:
        budgets[cpus] = budgets.get(cpus, 0) + 1
    for cpus in sorted(budgets):
        print('  cpus=%d: %d tasks' % (cpus, budgets[cpus]))
    for t, cpus, why in pinned:
        print('  %-36s cpus=%d  %s' % (t, cpus, why))
    for t, why in skipped:
        print('  SKIP %s: %s' % (t, why))
    if pinned and not args.apply:
        print('\n%d task environments let their thread pools oversubscribe their '
              'own CPU quota; re-run with --apply' % len(pinned))
    # A gate: an unpinned task can fail on thread thrashing alone, and a new task
    # can reintroduce that, so this must stay red until every one is pinned.
    return 1 if (skipped or (pinned and not args.apply)) else 0


if __name__ == '__main__':
    sys.exit(main())
