#!/usr/bin/env python3
"""Assemble the v3.2 publish tree from the v3.1 mirror + fresh drift-canyon records.

Layout: /mnt/data/v32-out/v3.2/<harness>/<provider>/<model>/<task>/...
Copies every record present in the v3.1 mirror, overlays the six fresh
drift-canyon records, and reports per-pair coverage gaps.
"""
import json, shutil, sys
from pathlib import Path

MIRROR = Path('/mnt/data/hf_v31_files/v3.1')
STAGE = Path('/mnt/data/v32-stage')
OUT = Path('/mnt/data/v32-out/v3.2')
SUITE_TASKS = sorted(p.name for p in
                     Path('/home/eewer/pi-setup/evals/general/tasks').iterdir()
                     if p.is_dir())

def main():
    if not MIRROR.exists():
        sys.exit('mirror missing')
    if OUT.exists():
        shutil.rmtree(OUT)
    total, gaps = 0, {}
    for harness in sorted(p for p in MIRROR.iterdir() if p.is_dir()):
        for provider in sorted(p for p in harness.iterdir() if p.is_dir()):
            for modeldir in sorted(p for p in provider.iterdir() if p.is_dir()):
                rel = modeldir.relative_to(MIRROR)
                dest = OUT / rel
                shutil.copytree(modeldir, dest, symlinks=False)
                have = {p.name for p in dest.iterdir() if p.is_dir()}
                missing = sorted(set(SUITE_TASKS) - have - {'drift-canyon'})
                gaps[str(rel)] = (len(have), missing)
                total += len(have)
    # overlay fresh drift-canyon records
    for src_task in STAGE.rglob('drift-canyon'):
        if src_task.is_dir():
            rel = src_task.relative_to(STAGE)
            dest_task = OUT / rel
            if dest_task.exists():
                shutil.rmtree(dest_task)
            shutil.copytree(src_task, dest_task)
            total += 1
    print(f'records assembled: {total}')
    for pair, (n, missing) in sorted(gaps.items()):
        tag = 'COMPLETE' if not missing else f'MISSING {len(missing)}: {missing}'
        print(f'  {pair}: {n} records | {tag}')
    # independence report
    shutil.copy('/home/eewer/pi-setup/evals/general/specs/independence_report.json',
                '/mnt/data/v32-out/v3.2/independence_report.json')
    print('independence_report.json staged')

if __name__ == '__main__':
    main()
