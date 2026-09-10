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

    # build_difficulty.py recomputes every bucket arithmetically from the rubric
    # total. The committed specs/difficulty.json does not follow that rule for 208
    # pre-existing tasks, and says so in its own `note`: their buckets came from
    # the frozen tb2.1 reference and are authoritative, so regenerating them
    # without that checkout silently relabels 208 published tasks and makes
    # check_difficulty.py fail against every task.toml. It happened during the
    # v4.1 wave and had to be repaired by hand.
    #
    # So snapshot the pre-existing buckets, let the tool add entries for tasks it
    # has not seen, and abort with the file restored if it moved one that was
    # already there. Reconciling the 208 is a deliberate act -- re-score those
    # rubrics or re-label those task.toml files -- not a side effect of running
    # the pipeline.
    diff_spec = ROOT / 'specs' / 'difficulty.json'
    before = json.loads(diff_spec.read_text()) if diff_spec.exists() else None
    run([py, 'tools/build_difficulty.py'])
    if before is not None and diff_spec.exists():
        after = json.loads(diff_spec.read_text())
        moved = sorted(
            t for t, rec in before.get('tasks', {}).items()
            if t in after.get('tasks', {})
            and rec.get('bucket') != after['tasks'][t].get('bucket'))
        if moved:
            diff_spec.write_text(json.dumps(before, indent=1) + '\n')
            print(f'FAILED: build_difficulty.py reassigned {len(moved)} '
                  f'pre-existing difficulty buckets ({", ".join(moved[:6])}'
                  f'{", ..." if len(moved) > 6 else ""}). specs/difficulty.json '
                  f'has been restored. See the note in that file: those buckets '
                  f'derive from the frozen tb2.1 reference and must not be '
                  f'recomputed from rubric totals. Reconcile them deliberately '
                  f'before regenerating.')
            sys.exit(1)

    # 3. provenance refresh (content freeze point)
    run([py, 'tools/update_provenance.py'])

    # 4. gates
    run([py, 'tools/selftest_binary_reward.py'])
    run([py, 'tools/check_binary_reward.py'])
    run([py, 'tools/ensure_reward_guard.py'])
    run([py, 'tools/pin_numeric_threads.py'])
    run([py, 'tools/ensure_git_safe_directory.py'])
    run([py, 'tools/pin_python_dependencies.py'])
    run([py, 'tools/check_general_coverage.py'])
    run([py, 'tools/check_tb21_coverage.py'])
    run([py, 'tools/lint_tasks.py'])
    run([py, 'tools/check_difficulty.py', '--allow-unmeasured'])
    run([py, 'tools/check_task_files_tracked.py'])
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
