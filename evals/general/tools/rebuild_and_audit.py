#!/usr/bin/env python3
"""Pipeline notes for rebuilding and auditing general-v2.

Unlike the v1 draft, v2 tasks are HAND-AUTHORED clean-room artifacts; there is
no generator to re-run.  "Rebuild" therefore means: verify the frozen
reference identity, regenerate the derived specs (coverage, difficulty),
refresh provenance, then run every gate and audit in fail-closed order.

Usage:
  bash tools/rebuild_and_audit.sh [REFERENCE_ROOT]

REFERENCE_ROOT defaults to the frozen path recorded in
specs/frozen_reference.json.
"""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(cmd):
    print(f'\n=== {" ".join(cmd)}')
    proc = subprocess.run(cmd, cwd=ROOT)
    if proc.returncode != 0:
        print(f'FAILED: {" ".join(cmd)}')
        sys.exit(proc.returncode)


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else None
    py = sys.executable

    # 1. frozen reference identity must verify
    run([py, 'tools/freeze_reference.py', '--verify'] +
        (['--reference-root', ref] if ref else []))

    # 2. derived specs
    run([py, 'tools/build_coverage.py'])
    run([py, 'tools/build_difficulty.py', '--allow-unmeasured']
        if False else [py, 'tools/build_difficulty.py'])

    # 3. provenance refresh (content freeze point)
    run([py, 'tools/update_provenance.py'])

    # 4. gates
    run([py, 'tools/check_general_coverage.py'])
    run([py, 'tools/check_tb21_coverage.py'])
    run([py, 'tools/lint_tasks.py'])
    run([py, 'tools/check_difficulty.py', '--allow-unmeasured'])
    run([py, 'tools/check_reproducibility.py'])
    run([py, 'tools/check_task_similarity.py'] +
        (['--reference-root', ref] if ref else []))

    # 5. byte-level independence audit
    run([py, 'tools/audit_independence.py'] +
        (['--reference-root', ref] if ref else []))

    # 6. suite-level completion report (archived outside task images)
    run([py, 'tools/suite_report.py'])

    print('\nrebuild_and_audit: ALL GATES PASSED')


if __name__ == '__main__':
    main()
