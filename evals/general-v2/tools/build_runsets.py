#!/usr/bin/env python3
"""Build symlinked runsets for multi-sample benchmark runs.

Harbor runs each directory under -p once; to draw N samples per task we expose
each task as N symlinked directories <task>--s<i>.  Usage:

  python3 tools/build_runsets.py [N]     # default N=2 -> 2 samples per task

The resulting runsets/general-v2-x<N>/ is passed to `harbor run -p`.
Sample count targets 200-500 trials: N is chosen so N * tasks falls in range.
"""
import os, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    tasks = sorted(p.name for p in (ROOT / 'tasks').iterdir()
                   if p.is_dir() and (p / 'task.toml').exists())
    n = int(sys.argv[1]) if len(sys.argv) > 1 else None
    if n is None:
        # smallest N with N * tasks >= 200, capped so N * tasks <= 500
        n = max(1, -(-200 // len(tasks)))
        if n * len(tasks) > 500:
            print(f'ERROR {len(tasks)} tasks cannot fit 200..500 samples '
                  'without exceeding the cap')
            return 1
    total = n * len(tasks)
    if not 200 <= total <= 500 and n > 1:
        print(f'WARNING {total} trials outside 200..500')
    out = ROOT / 'runsets' / f'general-v2-x{n}'
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for t in tasks:
        for s in range(1, n + 1):
            os.symlink(ROOT / 'tasks' / t, out / f'{t}--s{s}')
    print(f'runset {out}: {len(tasks)} tasks x {n} samples = {total} trials')
    return 0


if __name__ == '__main__':
    sys.exit(main())
