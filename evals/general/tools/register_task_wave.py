#!/usr/bin/env python3
"""Register a wave of authored tasks into the two suite-level specs.

Adds tasks to `specs/difficulty.json` and `specs/coverage_claims.json` without
touching any entry that is already there.

Why not just run tools/build_difficulty.py: that tool recomputes every task from
its own task-level difficulty.json, so any drift in the entries already recorded
gets rewritten. On this suite that flipped the bucket of 208 pre-existing tasks,
which is not a registration, it is an unrelated mass edit that also invalidates
reports quoting the old distribution. tools/rebuild_and_audit.py aborts when
buckets move, so the flip is loud rather than silent, but the fix is to not
cause it. This tool is additive by construction and asserts that no existing
entry changed.

Idempotent: a task already registered is reported and skipped, so a re-run after
a partial failure does not duplicate or overwrite.

Usage:
  python3 tools/register_task_wave.py --slots specs/v43c_slots.json \
      --wave "v4.3c real-issue wave" --dry-run
  python3 tools/register_task_wave.py --names a,b,c --wave "..." \
      --notes-file runs/v43c_review_notes.json

Does not commit. Review the diff, run the gates, then commit.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _toml_compat

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'
RUBRIC_KEYS = ['dependent_stages', 'tool_breadth', 'reasoning_depth',
               'debugging_ambiguity', 'adversarial_inputs',
               'hidden_case_generalization', 'quantitative_correctness',
               'resource_pressure', 'interaction_statefulness',
               'unsafe_action_penalty']
BUCKETS = {'easy': (0, 9), 'medium': (10, 17), 'hard': (18, 30)}
REQUIRED_FILES = ['instruction.md', 'task.toml', 'difficulty.json',
                  'environment/Dockerfile', 'tests/test.sh']


def bucket_for(total: int) -> str:
    for name, (lo, hi) in BUCKETS.items():
        if lo <= total <= hi:
            return name
    return 'hard'


def load_slots(path: Path) -> dict[str, dict]:
    """Map task name -> provenance, from either slots shape."""
    raw = json.loads(path.read_text())
    items = raw if isinstance(raw, list) else raw.get('slots') or []
    out = {}
    for s in items:
        if not isinstance(s, dict) or 'name' not in s:
            continue
        entry = s.get('entry') if isinstance(s.get('entry'), dict) else {}
        out[s['name']] = {
            'repository': s.get('repository') or entry.get('repository'),
            'parent_commit': entry.get('parent_commit'),
            'fix_commit': entry.get('fix_commit'),
            'upstream_issue_ref': entry.get('upstream_issue_ref'),
            'domain': s.get('domain') or entry.get('domain'),
        }
    return out


def detect_indent(path: Path, default: int = 2) -> int:
    """Match the indentation the file already uses.

    Both specs in this suite are written with indent=1. The first version of this
    tool wrote indent=2, which reformatted every line of both files: registering
    106 tasks produced a 29,922-insertion, 26,636-deletion diff in which the
    actual change was invisible and nothing could be reviewed. Content was
    provably unchanged, but a diff that large is how a real unintended edit hides.
    """
    try:
        with path.open() as f:
            f.readline()
            m = re.match(r'^( +)', f.readline() or '')
        return len(m.group(1)) if m else default
    except OSError:
        return default


def build_note(prov: dict, wave: str, extra: str | None) -> str:
    parts = [f'{wave}: independently authored task; see candidate and QA evidence.']
    if prov.get('repository') and prov.get('parent_commit'):
        chain = f"Built from a verified real upstream issue: repository {prov['repository']}, parent {prov['parent_commit']}"
        if prov.get('fix_commit'):
            chain += f", fix {prov['fix_commit']}"
        if prov.get('upstream_issue_ref'):
            chain += f", upstream issue reference {prov['upstream_issue_ref']}"
        chain += (' — the provenance chain that this task is a real reproducing '
                  'bug, recorded here because it exists nowhere else in the specs.')
        parts.append(chain)
    if prov.get('domain'):
        parts.append(f"Domain: {prov['domain']}.")
    if extra:
        parts.append(extra.strip())
    return ' '.join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=False)
    g.add_argument('--slots', type=Path, help='slots JSON with name/repository/entry')
    g.add_argument('--names', help='comma-separated task names')
    ap.add_argument('--wave',
                    help='label used in the coverage note, e.g. "v4.3c real-issue wave"')
    ap.add_argument('--notes-file', type=Path,
                    help='optional JSON mapping task name -> extra note text to append')
    ap.add_argument('--allow-missing-cpus', action='store_true',
                    help='do not reject tasks whose environment.cpus is not 1')
    ap.add_argument('--refresh-oracle-times', action='store_true',
                    help='only fill oracle_time_sec/oracle_reward on already-registered '
                         'tasks from specs/oracle_times.json; add nothing. Needed because '
                         'the census runs after registration, and check_difficulty.py '
                         'fails on tasks with no measured oracle time.')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--candidate-dir', type=Path, default=ROOT / 'authoring/candidates')
    ap.add_argument('--qa-root', type=Path, default=ROOT / 'qa/results')
    args = ap.parse_args()

    diff_p = ROOT / 'specs' / 'difficulty.json'
    claims_p = ROOT / 'specs' / 'coverage_claims.json'
    times_p = ROOT / 'specs' / 'oracle_times.json'
    diff = json.loads(diff_p.read_text())
    claims = json.loads(claims_p.read_text())
    times = json.loads(times_p.read_text()) if times_p.exists() else {}

    if args.refresh_oracle_times:
        before = dict(diff['tasks'])
        filled, unchanged = [], []
        for name, rec in times.items():
            e = diff['tasks'].get(name)
            if not isinstance(e, dict) or not isinstance(rec, dict):
                continue
            t, r = rec.get('oracle_time_sec'), rec.get('reward')
            if e.get('oracle_time_sec') == t and e.get('oracle_reward') == r:
                unchanged.append(name)
                continue
            # Only these two fields may move. Touching a rubric or a bucket here
            # would be a silent re-grading of a committed task.
            e['oracle_time_sec'] = t
            e['oracle_reward'] = r
            filled.append(name)
        drifted = [k for k, v in before.items()
                   if k not in filled
                   and json.dumps(diff['tasks'][k], sort_keys=True)
                   != json.dumps(v, sort_keys=True)]
        if drifted:
            print(f'ABORT: refresh touched tasks outside oracle_times: {drifted[:10]}')
            return 2
        counts = {b: sum(1 for t in diff['tasks'].values() if t['bucket'] == b)
                  for b in BUCKETS}
        counts['total'] = len(diff['tasks'])
        still_missing = sorted(k for k, v in diff['tasks'].items()
                               if v.get('oracle_time_sec') is None)
        print(f'refreshed oracle timings: filled={len(filled)} already_current={len(unchanged)}')
        print(f'suite_counts unchanged: {counts}')
        print(f'still without an oracle time: {len(still_missing)}')
        if still_missing[:8]:
            print(f'  e.g. {", ".join(still_missing[:8])}')
        if args.dry_run:
            print('\nDRY RUN: nothing written.')
            return 0
        diff_p.write_text(json.dumps(diff, indent=detect_indent(diff_p)) + '\n')
        print(f'\nwrote {diff_p.relative_to(ROOT)}')
        return 0

    if args.slots:
        prov_all = load_slots(args.slots)
        names = sorted(prov_all)
    elif args.names:
        names = [n.strip() for n in args.names.split(',') if n.strip()]
        prov_all = {n: {} for n in names}
    else:
        ap.error('one of --slots or --names is required unless '
                 '--refresh-oracle-times is given')

    extra_notes = {}
    if args.notes_file:
        if args.notes_file.exists():
            extra_notes = json.loads(args.notes_file.read_text())
        else:
            print(f'WARN: --notes-file {args.notes_file} does not exist; '
                  'registering without per-task notes')

    diff = json.loads(diff_p.read_text())
    claims = json.loads(claims_p.read_text())
    times = json.loads(times_p.read_text()) if times_p.exists() else {}

    before_tasks = dict(diff['tasks'])
    before_claims = {k: json.dumps(v, sort_keys=True) for k, v in claims.items()}

    added, skipped, rejected = [], [], []
    for name in names:
        d = TASKS / name
        prov = prov_all.get(name, {})
        missing = [f for f in REQUIRED_FILES if not (d / f).exists()]
        if missing:
            rejected.append(f'{name}: incomplete, missing {missing}')
            continue
        if name in diff['tasks'] and name in claims:
            skipped.append(name)
            continue

        # Newly registered tasks require acceptance for exactly these bytes.
        from author_task import validate, fingerprint
        try:
            candidate = validate(json.loads((args.candidate_dir / f'{name}.json').read_text()))
            if candidate['task_id'] != name:
                raise ValueError('candidate task_id mismatch')
            digest = fingerprint(d, candidate)
            accepted = False
            qa_receipt = None
            for report_path in args.qa_root.glob(f'{name}-*/report.json'):
                report = json.loads(report_path.read_text())
                if report.get('task_id') == name and report.get('fingerprint') == digest and report.get('status') == 'accepted' and report.get('errors') == []:
                    accepted = True
                    qa_receipt = report_path
            if not accepted:
                raise ValueError('no accepted QA report for current package')
            prov = dict(candidate['source'])
            prov.setdefault('parent_commit', prov.get('base_commit'))
            prov.setdefault('upstream_issue_ref', prov.get('reference'))
            measured = qa_receipt.parent / 'oracle-result.json'
            oracle_metrics = json.loads(measured.read_text()) if measured.exists() else {}
        except (OSError, ValueError, TypeError) as exc:
            rejected.append(f'{name}: {exc}')
            continue

        dd = json.loads((d / 'difficulty.json').read_text())
        rub = dd.get('rubric') or {}
        bad = [k for k in RUBRIC_KEYS if not isinstance(rub.get(k), int)]
        if bad:
            rejected.append(f'{name}: rubric missing or non-integer for {bad}')
            continue
        toml = _toml_compat.loads((d / 'task.toml').read_text())
        env = toml.get('environment') or {}
        cpus = env.get('cpus')
        if cpus != 1 and not args.allow_missing_cpus:
            rejected.append(f'{name}: environment.cpus is {cpus!r}, expected 1 '
                            '(single-CPU constraint); pass --allow-missing-cpus to override')
            continue

        total = sum(rub[k] for k in RUBRIC_KEYS)
        entry = {
            'rubric': {k: rub.get(k) for k in RUBRIC_KEYS},
            'total': total,
            'bucket': bucket_for(total),
            'task_toml_difficulty': (toml.get('metadata') or {}).get('difficulty'),
            'expected_expert_time_min': dd.get('expected_expert_time_min'),
            'documented_probe': dd.get('documented_probe'),
            'oracle_time_sec': oracle_metrics.get('elapsed_seconds', (times.get(name) or {}).get('oracle_time_sec')),
            'oracle_reward': 1 if oracle_metrics.get('reward') in ('1', '1.0') else (times.get(name) or {}).get('reward'),
            'verifier_timeout_sec': (toml.get('verifier') or {}).get('timeout_sec'),
            'agent_timeout_sec': (toml.get('agent') or {}).get('timeout_sec'),
            'memory_mb': env.get('memory_mb'),
            'cpus': cpus,
            'notes': dd.get('notes', ''),
            'authoring_pipeline': candidate['pipeline'],
            'candidate_fingerprint': digest,
            'qa_report': str(qa_receipt.resolve().relative_to(ROOT)) if qa_receipt.resolve().is_relative_to(ROOT) else str(qa_receipt.resolve()),
        }
        if name not in diff['tasks']:
            diff['tasks'][name] = entry
        if name not in claims:
            claims[name] = {
                'competencies': [],
                'evidence': {},
                'note': build_note(prov, args.wave, extra_notes.get(name)),
                # Compatibility field for existing release metadata.
                'claims_no_competencies': True,
            }
        added.append((name, entry['bucket'], entry['total']))

    # The whole point of this tool: prove nothing already recorded was touched.
    changed = [k for k, v in before_tasks.items()
               if json.dumps(diff['tasks'].get(k), sort_keys=True)
               != json.dumps(v, sort_keys=True)]
    gone = [k for k in before_tasks if k not in diff['tasks']]
    claims_changed = [k for k, v in before_claims.items()
                      if json.dumps(claims.get(k), sort_keys=True) != v]
    if changed or gone or claims_changed:
        print('ABORT: this tool must be purely additive.')
        if changed:
            print(f'  difficulty entries modified: {changed[:10]}')
        if gone:
            print(f'  difficulty entries dropped: {gone[:10]}')
        if claims_changed:
            print(f'  coverage claims modified: {claims_changed[:10]}')
        return 2

    counts = {b: sum(1 for t in diff['tasks'].values() if t['bucket'] == b)
              for b in BUCKETS}
    counts['total'] = len(diff['tasks'])
    diff['suite_counts'] = counts

    new_counts = {b: sum(1 for _n, bk, _t in added if bk == b) for b in BUCKETS}

    print(f'wave label      : {args.wave}')
    print(f'candidates      : {len(names)}')
    print(f'added           : {len(added)}  buckets={new_counts}')
    print(f'skipped (already registered): {len(skipped)}')
    print(f'rejected        : {len(rejected)}')
    for r in rejected:
        print(f'  REJECT {r}')
    print(f'suite now       : {counts}')

    if args.dry_run:
        print('\nDRY RUN: nothing written.')
        return 0

    diff_p.write_text(json.dumps(diff, indent=detect_indent(diff_p)) + '\n')
    claims_p.write_text(json.dumps(claims, indent=detect_indent(claims_p)) + '\n')
    print(f'\nwrote {diff_p.relative_to(ROOT)} and {claims_p.relative_to(ROOT)}')
    print('Not committed. Next: review the additive registration and preserve '
          'candidate, QA report, and review evidence with the release.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
