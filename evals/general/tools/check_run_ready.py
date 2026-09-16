#!/usr/bin/env python3
"""Pre-flight check for a benchmark run.

Validates the things that actually break a 1075-trial run, in one command, before
hours of compute are committed to it. Every check here corresponds to a failure
mode this suite has hit or is one accident away from:

  - a wrong harbor version. Two incompatible CLIs are installed on this box
    (0.18.0 takes --env, 0.22.0 produced every published record). Runs under
    different versions do not compare, and nothing else complains.
  - a missing base image. Every task FROMs one of three bench-base tags, so a
    pruned base fails every build in the suite at once.
  - insufficient disk. Images are 0.5-5 GB each and the run builds far more than
    fits; without the reclaim guard active the run dies partway.
  - a dirty tree. A run against uncommitted changes is not reproducible and
    cannot be matched to the records it produces.
  - provenance drift, a broken runset symlink, or a gate that has gone red since
    the last time anyone looked.

Exit 0 only if every REQUIRED check passes. Advisories never fail the run.

Usage:
  python3 tools/check_run_ready.py             # full check including gates
  python3 tools/check_run_ready.py --fast      # skip the slow gate sweep
  python3 tools/check_run_ready.py --json      # machine-readable
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _toml_compat

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]

# The version every published record was produced with. See
# runs/harbor-requirements.txt for why this is pinned rather than "any harbor".
HARBOR_VERSION = '0.22.0'
BASE_IMAGES = ['bench-base:python-3.12', 'bench-base:ubuntu-24.04',
               'bench-base:node-22']
# Free disk below which a full run will stall even with the guard reclaiming.
DISK_MIN_GB = 60
DISK_WARN_GB = 120
GATES = [
    'check_binary_reward.py',
    'ensure_reward_guard.py',
    'lint_tasks.py',
    'check_difficulty.py --allow-unmeasured',
    'check_upstream_disjointness.py',
    'check_tb21_coverage.py',
    'build_coverage.py',
    'check_reproducibility.py',
    'check_task_files_tracked.py',
    'check_image_size_hygiene.py',
    'pin_numeric_threads.py',
    'ensure_git_safe_directory.py',
    'pin_python_dependencies.py',
]


def run(cmd: list[str] | str, cwd: Path | None = None, timeout: int = 900):
    try:
        p = subprocess.run(cmd, shell=isinstance(cmd, str), cwd=cwd,
                           capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or '') + (p.stderr or '')
    except subprocess.TimeoutExpired:
        return 124, 'timed out'
    except OSError as e:
        return 127, str(e)


class Report:
    def __init__(self):
        self.rows: list[tuple[str, str, str, str]] = []  # level, name, detail, hint

    def ok(self, name, detail=''):
        self.rows.append(('PASS', name, detail, ''))

    def warn(self, name, detail, hint=''):
        self.rows.append(('WARN', name, detail, hint))

    def fail(self, name, detail, hint=''):
        self.rows.append(('FAIL', name, detail, hint))

    @property
    def failed(self):
        return [r for r in self.rows if r[0] == 'FAIL']

    @property
    def warned(self):
        return [r for r in self.rows if r[0] == 'WARN']


def check_harbor(r: Report):
    path = shutil.which('harbor')
    if not path:
        for cand in ('/tmp/venv-recreate/bin/harbor',):
            if Path(cand).exists():
                path = cand
                break
    if not path:
        r.fail('harbor binary',
               'not on PATH and not at /tmp/venv-recreate/bin/harbor',
               'recreate the venv per runs/harbor-requirements.txt')
        return None
    rc, out = run([path, '--version'], timeout=60)
    ver = out.strip().splitlines()[-1].strip() if out.strip() else ''
    if rc != 0:
        r.fail('harbor binary', f'{path} did not report a version: {out[:120]}')
        return None
    if HARBOR_VERSION not in ver:
        r.fail('harbor version',
               f'{path} reports {ver!r}, expected {HARBOR_VERSION}',
               'two incompatible CLIs are installed here; runs under different '
               'versions do not compare. Use the venv in runs/harbor-requirements.txt')
    else:
        r.ok('harbor', f'{ver} at {path}')
    return path


def check_docker(r: Report):
    rc, out = run(['docker', 'info', '--format', '{{.ServerVersion}}'], timeout=60)
    if rc != 0:
        r.fail('docker daemon', f'not responsive: {out.strip()[:140]}')
        return
    r.ok('docker daemon', f'server {out.strip()}')
    rc, out = run(['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}'],
                  timeout=120)
    present = set(out.split()) if rc == 0 else set()
    missing = [b for b in BASE_IMAGES if b not in present]
    if missing:
        r.fail('base images', f'missing: {", ".join(missing)}',
               'every task FROMs one of these; rebuild with runs/build-bases.sh')
    else:
        r.ok('base images', f'all {len(BASE_IMAGES)} present')


def check_disk(r: Report):
    free = shutil.disk_usage('/').free / 1e9
    if free < DISK_MIN_GB:
        r.fail('disk headroom', f'{free:.0f} GB free, need at least {DISK_MIN_GB}',
               'the run builds 0.5-5 GB images; reclaim before starting')
    elif free < DISK_WARN_GB:
        r.warn('disk headroom', f'{free:.0f} GB free',
               'workable, but the reclaim guard must be running for a full pass')
    else:
        r.ok('disk headroom', f'{free:.0f} GB free')
    # The guard is what keeps a long run alive; without it the run dies partway.
    rc, out = run(['pgrep', '-f', 'disk-keeper'], timeout=30)
    if rc != 0 or not out.strip():
        r.warn('disk reclaim guard', 'no disk-keeper process found',
               'start it, e.g. bash runs/disk-keeper-v41.sh 75 72 45 72 50')
    else:
        r.ok('disk reclaim guard', f'running (pid {out.split()[0]})')


def check_tree(r: Report):
    rc, out = run(['git', 'status', '--short'], cwd=REPO, timeout=120)
    dirty = [ln for ln in out.splitlines() if ln.strip()]
    if rc != 0:
        r.warn('git state', f'could not read: {out.strip()[:100]}')
    elif dirty:
        r.fail('clean tree', f'{len(dirty)} uncommitted path(s), e.g. {dirty[0][:70]}',
               'a run against uncommitted changes cannot be matched to its records')
    else:
        r.ok('clean tree', 'nothing uncommitted')
    rc, out = run(['git', 'rev-parse', '--short', 'HEAD'], cwd=REPO, timeout=60)
    if rc == 0:
        # run() returns (rc, out); unpacking it the other way round binds the
        # return code and then fails on .strip().
        brc, br = run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], cwd=REPO,
                      timeout=60)
        branch = br.strip() if brc == 0 else 'unknown'
        r.ok('commit', f'{out.strip()} on {branch}')


def check_tasks(r: Report):
    tasks = [p for p in (ROOT / 'tasks').iterdir()
             if p.is_dir() and (p / 'task.toml').exists()]
    if not tasks:
        r.fail('task tree', 'no tasks found')
        return len(tasks)
    r.ok('task count', f'{len(tasks)} tasks with a task.toml')

    # A task with no verifier, no oracle or no instruction cannot be scored.
    incomplete = []
    for t in tasks:
        for need in ('instruction.md', 'tests/test.sh'):
            if not (t / need).exists():
                incomplete.append(f'{t.name} missing {need}')
    if incomplete:
        r.fail('task completeness', f'{len(incomplete)} problem(s)',
               '; '.join(incomplete[:4]))
    else:
        r.ok('task completeness', 'every task has an instruction and a verifier')

    # cpus must be a positive integer; a task declaring none gets no quota.
    bad = []
    multi = 0
    for t in tasks:
        try:
            env = (_toml_compat.loads((t / 'task.toml').read_text())
                   .get('environment') or {})
        except Exception as e:
            bad.append(f'{t.name}: unparsable task.toml ({e})')
            continue
        c = env.get('cpus')
        if not isinstance(c, int) or c < 1:
            bad.append(f'{t.name}: cpus={c!r}')
        elif c > 1:
            multi += 1
    if bad:
        r.fail('cpu quota declared', f'{len(bad)} task(s)', '; '.join(bad[:4]))
    else:
        r.ok('cpu quota declared',
             f'all {len(tasks)} declare an integer cpus; {multi} use more than 1 '
             '(documented exception, see WORKFLOW.md "CPU quota")')
    return len(tasks)


def check_runset(r: Report, n_tasks: int):
    rs = ROOT / 'runsets'
    if not rs.exists():
        r.warn('runset', 'not built yet',
               'run: python3 tools/build_runsets.py')
        return
    sets = [p for p in rs.iterdir() if p.is_dir()]
    if not sets:
        r.warn('runset', 'runsets/ exists but is empty')
        return
    for s in sets:
        links = list(s.iterdir())
        broken = [l.name for l in links if l.is_symlink() and not l.exists()]
        if broken:
            r.fail('runset integrity', f'{s.name}: {len(broken)} broken symlink(s), '
                                       f'e.g. {broken[0]}')
        elif len(links) < n_tasks:
            r.warn('runset size', f'{s.name} has {len(links)} entries for '
                                  f'{n_tasks} tasks',
                   'rebuild it: python3 tools/build_runsets.py')
        else:
            r.ok('runset', f'{s.name}: {len(links)} entries, 0 broken')


def check_gates(r: Report):
    for g in GATES:
        rc, out = run(f'python3 tools/{g}', cwd=ROOT, timeout=1800)
        tail = [ln for ln in out.strip().splitlines() if ln.strip()]
        detail = tail[-1][:88] if tail else ''
        if rc != 0:
            r.fail(f'gate {g.split()[0]}', f'exit {rc}: {detail}')
        else:
            r.ok(f'gate {g.split()[0]}', detail)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fast', action='store_true',
                    help='skip the gate sweep (which re-runs 13 tools)')
    ap.add_argument('--json', action='store_true')
    args = ap.parse_args()

    r = Report()
    check_docker(r)
    check_harbor(r)
    check_disk(r)
    n = check_tasks(r)
    check_tree(r)
    check_runset(r, n)
    if not args.fast:
        check_gates(r)

    if args.json:
        print(json.dumps({
            'ready': not r.failed,
            'failures': [{'check': n_, 'detail': d, 'hint': h}
                         for _l, n_, d, h in r.failed],
            'warnings': [{'check': n_, 'detail': d, 'hint': h}
                         for _l, n_, d, h in r.warned],
            'passed': [n_ for _l, n_, _d, _h in r.rows if _l == 'PASS'],
        }, indent=1))
    else:
        for level, name, detail, hint in r.rows:
            print(f'  [{level}] {name}: {detail}')
            if hint and level != 'PASS':
                print(f'         -> {hint}')
        print()
        print(f'{len(r.rows) - len(r.failed) - len(r.warned)} passed, '
              f'{len(r.warned)} warning(s), {len(r.failed)} failure(s)')
        if r.failed:
            print('\nNOT READY TO RUN.')
        else:
            print('\nREADY TO RUN.' + (' (with warnings above)' if r.warned else ''))
    return 1 if r.failed else 0


if __name__ == '__main__':
    sys.exit(main())
