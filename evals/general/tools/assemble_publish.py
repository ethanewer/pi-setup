#!/usr/bin/env python3
"""Assemble a publish tree of run records and prove it is complete.

Layout in and out:

    <harness>/<provider>/<model>/<task>/{metadata.json,trajectory.json,
                                         verifier/reward.txt,
                                         verifier/test-stdout.txt}

Carries every record forward from a previous published tree, overlays fresh
records on top, then validates the result against the live suite and writes the
per-pair and top-level aggregates that the tree is supposed to ship with.

The validation is fail-closed, because the v3.2 publish was not. That tree
reported itself complete while an entire harness/model pair was missing 530
records, 22 records shipped with no verifier/reward.txt at all, and no
results.json was generated for any pair. None of those were detectable from the
tree itself afterwards, so this tool refuses to write a tree it cannot account
for.

Checks, all of which must pass:
  * every harness/provider/model pair in the source appears in the output
  * every task in the suite has a record in every pair, and no record exists
    for a task that is not in the suite
  * every record has all four files
  * every reward.txt parses as a number and is exactly 0 or 1, per the binary
    reward contract enforced by tools/check_binary_reward.py

Usage:
  python3 tools/assemble_publish.py --version v3.3 \
      --mirror /path/to/v3.2 --out /path/to/out \
      [--overlay /path/to/fresh-records]... [--report-only]

--report-only validates an existing tree in place and writes nothing.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

REQUIRED = ('metadata.json', 'trajectory.json',
            'verifier/reward.txt', 'verifier/test-stdout.txt')
PAIR_DEPTH = 3          # harness / provider / model
TASK_DEPTH = 4


def suite_tasks(suite_root: Path):
    d = suite_root / 'tasks'
    if not d.is_dir():
        raise SystemExit(f'no tasks directory at {d}')
    return sorted(p.name for p in d.iterdir() if p.is_dir())


def read_reward(p: Path):
    """Return (value, problem). value is None when the reward is unusable."""
    try:
        raw = p.read_text().strip()
    except Exception as e:
        return None, f'unreadable ({e})'
    if not raw:
        return None, 'empty'
    try:
        val = float(raw)
    except ValueError:
        return None, f'not a number: {raw!r}'
    if val not in (0.0, 1.0):
        return val, f'not binary: {raw!r}'
    return val, ''


def records_under(root: Path):
    """Yield (pair, task, record_dir) for every record in a publish tree."""
    for meta in sorted(root.rglob('metadata.json')):
        rel = meta.parent.relative_to(root).parts
        if len(rel) != TASK_DEPTH:
            continue
        yield '/'.join(rel[:PAIR_DEPTH]), rel[3], meta.parent


def audit(out: Path, tasks, pairs_expected):
    """Return (problems, per_pair_stats) for an assembled tree."""
    problems = []
    have = {}
    seen_pairs = set()
    for pair, task, rec in records_under(out):
        seen_pairs.add(pair)
        have.setdefault(pair, {})[task] = rec

    for pair in sorted(pairs_expected - seen_pairs):
        problems.append(f'pair missing entirely from output: {pair}')
    for pair in sorted(seen_pairs - pairs_expected):
        problems.append(f'pair in output but not in any source: {pair}')

    stats = {}
    for pair in sorted(seen_pairs | pairs_expected):
        recs = have.get(pair, {})
        names = set(recs)
        missing = sorted(t for t in tasks if t not in names)
        unknown = sorted(names - set(tasks))
        incomplete, unscoreable, nonbinary = [], [], []
        total, strict = 0.0, 0
        for task in sorted(names):
            rec = recs[task]
            absent = [f for f in REQUIRED if not (rec / f).is_file()]
            if absent:
                incomplete.append((task, absent))
            rp = rec / 'verifier/reward.txt'
            if rp.is_file():
                val, prob = read_reward(rp)
                if prob.startswith('not binary'):
                    nonbinary.append((task, prob))
                elif val is None:
                    unscoreable.append((task, prob))
                else:
                    total += val
                    strict += 1 if val == 1.0 else 0
            else:
                unscoreable.append((task, 'no verifier/reward.txt'))
        for t in missing:
            problems.append(f'{pair}: no record for suite task {t}')
        for t in unknown:
            problems.append(f'{pair}: record for {t} which is not in the suite')
        for t, absent in incomplete:
            problems.append(f'{pair}/{t}: missing {", ".join(absent)}')
        for t, prob in unscoreable:
            problems.append(f'{pair}/{t}: unscoreable, {prob}')
        for t, prob in nonbinary:
            problems.append(f'{pair}/{t}: {prob}')
        stats[pair] = {
            'records': len(names),
            'suite_tasks': len(tasks),
            'missing': missing,
            'scored': len(names) - len(unscoreable),
            'unscoreable': [t for t, _ in unscoreable],
            'non_binary': [t for t, _ in nonbinary],
            'incomplete': [t for t, _ in incomplete],
            'total_reward': round(total, 4),
            'strict_pass': strict,
        }
    return problems, stats


def write_aggregates(out: Path, version: str, tasks, stats, suite_root: Path,
                     notes=(), sources=()):
    """Write the per-pair results.json and the top-level summary.json."""
    n = len(tasks)
    for pair, s in sorted(stats.items()):
        harness, provider, model = pair.split('/')
        denom = s['scored'] or 1
        payload = {
            'suite': f'general-agent-bench {version}',
            'harness': harness,
            'provider': provider,
            'model': model,
            'suite_tasks': n,
            'records': s['records'],
            'scored': s['scored'],
            'unscoreable': s['unscoreable'],
            'total_reward': s['total_reward'],
            'strict_pass': s['strict_pass'],
            # mean reward over scored records; equals the pass rate now that
            # every reward is binary, and the denominator is stated so the two
            # can never be confused again
            'mean_reward_scored': round(s['total_reward'] / denom, 6),
            'strict_pass_rate_scored': round(s['strict_pass'] / denom, 6),
            'mean_reward_all_suite_tasks': round(s['total_reward'] / n, 6),
            'reward_contract': 'binary: every reward.txt is exactly 0 or 1',
        }
        (out / pair).mkdir(parents=True, exist_ok=True)
        (out / pair / 'results.json').write_text(
            json.dumps(payload, indent=1) + '\n')

    scored_pairs = {p: s for p, s in stats.items() if s['unscoreable'] == []}
    summary = {
        'suite': f'general-agent-bench {version}',
        'tasks': n,
        'pairs': len(stats),
        'pairs_fully_scored': len(scored_pairs),
        'reward_contract': 'binary: every reward.txt is exactly 0 or 1',
        'leaderboard': [
            {'pair': p,
             'total_reward': s['total_reward'],
             'strict_pass': s['strict_pass'],
             'scored': s['scored'],
             'pass_rate': round(s['strict_pass'] / (s['scored'] or 1), 6)}
            for p, s in sorted(stats.items(),
                               key=lambda kv: -kv[1]['strict_pass'])
        ],
        'unscoreable_records': {p: s['unscoreable'] for p, s in sorted(stats.items())
                                if s['unscoreable']},
        # what this version changed, and which trees it was built from. v3.2
        # shipped a summary with no aggregates and no account of its own
        # provenance, so nobody could tell afterwards which records were carried
        # over and which were new.
        'notes': list(notes),
        'sources': list(sources),
    }
    (out / 'summary.json').write_text(json.dumps(summary, indent=1) + '\n')
    return summary


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', required=True, help='e.g. v3.3')
    ap.add_argument('--mirror', type=Path, help='previous published tree to carry over')
    ap.add_argument('--out', type=Path, help='tree to write (or validate with --report-only)')
    ap.add_argument('--overlay', type=Path, action='append', default=[],
                    help='fresh records to overlay; repeatable, later wins')
    ap.add_argument('--suite-root', type=Path,
                    default=Path(__file__).resolve().parents[1])
    ap.add_argument('--report-only', action='store_true',
                    help='validate --out in place and write nothing')
    ap.add_argument('--note', action='append', default=[], metavar='TEXT',
                    help='provenance line for summary.json; repeatable')
    args = ap.parse_args()

    if not args.out:
        ap.error('--out is required')
    tasks = suite_tasks(args.suite_root)

    sources = [d for d in ([args.mirror] + args.overlay) if d]
    for d in sources:
        if not d.is_dir():
            raise SystemExit(f'source tree missing: {d}')
    pairs_expected = set()
    for d in sources:
        for rec_pair, _, _ in records_under(d):
            pairs_expected.add(rec_pair)
    if not pairs_expected:
        raise SystemExit('no records found in any source tree')

    if args.report_only:
        problems, stats = audit(args.out, tasks, pairs_expected)
    else:
        if args.out.exists():
            shutil.rmtree(args.out)
        if args.mirror:
            for pair, task, rec in records_under(args.mirror):
                dest = args.out / pair / task
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(rec, dest, symlinks=False)
        for ov in args.overlay:
            for pair, task, rec in records_under(ov):
                dest = args.out / pair / task
                if dest.exists():
                    shutil.rmtree(dest)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(rec, dest, symlinks=False)
        # a pair that exists in an overlay but not the mirror is still a pair
        for pair, _, _ in records_under(args.out):
            pairs_expected.add(pair)
        problems, stats = audit(args.out, tasks, pairs_expected)

    print(f'suite tasks: {len(tasks)}   pairs: {len(stats)}')
    for pair, s in sorted(stats.items()):
        tag = 'COMPLETE' if not (s['missing'] or s['unscoreable'] or
                                 s['non_binary'] or s['incomplete']) else 'GAPS'
        print(f"  {pair:52s} {s['records']:4d}/{s['suite_tasks']} "
              f"scored={s['scored']:4d} reward={s['total_reward']:7.2f} "
              f"pass={s['strict_pass']:4d}  {tag}")
        for label in ('missing', 'unscoreable', 'non_binary', 'incomplete'):
            if s[label]:
                shown = s[label][:12]
                more = f' ... (+{len(s[label]) - 12} more)' if len(s[label]) > 12 else ''
                print(f'      {label}: {len(s[label])} {shown}{more}')

    if not args.report_only and not problems:
        summary = write_aggregates(args.out, args.version, tasks, stats,
                                   args.suite_root, notes=args.note,
                                   sources=[str(d) for d in sources])
        # stage the audit bundle that is available locally. These are gitignored
        # generated artifacts, so a clone that never ran the audits ships without
        # them; say so instead of quietly publishing a tree with no audit trail.
        staged, absent = [], []
        for name in ('independence_report.json', 'similarity_report.json',
                     'oracle_report.json', 'oracle_times.json'):
            src = args.suite_root / 'specs' / name
            if src.is_file():
                shutil.copy(src, args.out / name)
                staged.append(name)
                continue
            # these are gitignored generated artifacts, so a clone that never ran
            # the audits has none. Carry the mirror's copy forward rather than
            # publishing a tree that silently dropped the audit trail the
            # previous version shipped.
            carried = args.mirror / name if args.mirror else None
            if carried and carried.is_file():
                shutil.copy(carried, args.out / name)
                staged.append(f'{name} (carried from mirror)')
            else:
                absent.append(name)
        waivers = args.suite_root / 'specs/infeasible_waivers.json'
        if waivers.is_file():
            shutil.copy(waivers, args.out / 'infeasible_waivers.json')
            staged.append('infeasible_waivers.json')
        for name in ('coverage.json', 'difficulty.json', 'tb21_competencies.json',
                     'frozen_reference.json', 'provenance.json'):
            src = args.suite_root / 'specs' / name
            if src.is_file():
                (args.out / 'audit').mkdir(parents=True, exist_ok=True)
                shutil.copy(src, args.out / 'audit' / name)
                staged.append(f'audit/{name}')
        print(f'staged audit bundle: {", ".join(staged)}')
        if absent:
            print('WARN absent (gitignored, regenerate before publishing): '
                  + ', '.join(absent))
        print(f"wrote {summary['pairs']} results.json + summary.json")

    if problems:
        print(f'\nPROBLEMS: {len(problems)}')
        for p in problems[:40]:
            print('  ', p)
        if len(problems) > 40:
            print(f'   ... and {len(problems) - 40} more')
        return 1
    print('\nassemble_publish: tree is complete and binary')
    return 0


if __name__ == '__main__':
    sys.exit(main())
