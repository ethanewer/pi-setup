#!/usr/bin/env python3
"""Generate prerequisite campaign skills in one isolated, budgeted Luna call."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import threading
import time

from generate_tasks import (EFFORT, MODEL, Queue, luna_usage_cost, run_process, seal,
                            session_context, usage_from_events, verify_seal)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--prompt', type=Path, required=True)
    parser.add_argument('--reserve-dollars', type=float, required=True)
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--recover-completed', action='store_true')
    args = parser.parse_args()
    queue = Queue(args.db)
    ident = 'skill-batch-' + hashlib.sha256(args.prompt.read_bytes()).hexdigest()[:16]
    output = args.workspace.resolve()
    if args.recover_completed:
        result = json.loads((output / 'result.json').read_text())
        if result.get('status') != 'passed' or result.get('candidate_id') != ident:
            raise ValueError('recovery requires the completed matching result')
        shutil.rmtree(output / '.tmp', ignore_errors=True)
        (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
        result['seal_sha256'] = verify_seal(output)
        queue.control.account_storage(output, ident)
        with queue.connect() as db:
            row = db.execute("SELECT * FROM stage_attempts WHERE candidate_id=? AND stage='author' AND state='running' ORDER BY started DESC LIMIT 1", (ident,)).fetchone()
        if row is None:
            raise ValueError('no recoverable running stage')
        claim = {'token': row['token']}
        # Recovery is allowed only after the recorded worker process is gone;
        # fence the prior lease transactionally before finalizing its sealed bytes.
        with queue.connect() as db:
            db.execute('UPDATE stage_attempts SET lease=? WHERE token=? AND state="running"',
                       (time.time() + 120, row['token']))
        queue.control.finish_stage(claim, 'passed', result)
        if row['reservation_token']:
            queue.control.reconcile(row['reservation_token'], result['calculated_dollars'])
        print(json.dumps(result, indent=2))
        return 0
    reservation = queue.control.reserve('author', ident, args.reserve_dollars)
    claim = queue.control.claim_stage(ident, 'author', args.timeout + 120, reservation)
    work = output / 'workspace'
    work.mkdir(parents=True, exist_ok=False)
    (work / 'skills').mkdir()
    (work / 'prompt.txt').write_bytes(args.prompt.read_bytes())
    result = {'kind': 'skill_generation', 'candidate_id': ident, 'bundle': str(output),
              'model': MODEL, 'reasoning_effort': EFFORT}
    try:
        with (work / 'prompt.txt').open() as source:
            code = run_process(['codex', '-a', 'never', 'exec', '--ignore-user-config',
                '-m', MODEL, '-c', 'model_reasoning_effort="medium"',
                '-s', 'workspace-write', '-c', 'sandbox_workspace_write.network_access=true',
                '--skip-git-repo-check', '-C', str(work), '--json',
                '-o', str(work / 'final.txt'), '-'], work, output / 'events.jsonl',
                output / 'stderr.log', args.timeout, threading.Event(), source)
        if code:
            raise ValueError(f'skill generator exited {code}')
        skills = []
        for path in sorted((work / 'skills').glob('*/SKILL.md')):
            content = path.read_text()
            if not content.startswith('---\n') or '\nname:' not in content or '\ndescription:' not in content:
                raise ValueError(f'invalid skill frontmatter: {path}')
            skills.append({'path': str(path.relative_to(work)),
                           'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        if len(skills) != 8:
            raise ValueError(f'expected 8 skills, found {len(skills)}')
        result.update(status='passed', skills=skills)
    except (OSError, ValueError, TimeoutError) as exc:
        result.update(status='failed', error=str(exc))
    result['usage'], result['thread_id'] = usage_from_events(output / 'events.jsonl')
    try:
        result['session_context'] = session_context(result['thread_id'])
    except ValueError as exc:
        result.update(status='failed', error=str(exc))
    usage = result['usage']
    actual = luna_usage_cost(usage)
    result['calculated_dollars'] = actual
    shutil.rmtree(output / '.tmp', ignore_errors=True)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    result['seal_sha256'] = verify_seal(output)
    queue.control.account_storage(output, ident)
    queue.control.finish_stage(claim, 'passed' if result['status'] == 'passed' else 'failed', result)
    metered = bool(result['usage'])
    queue.control.reconcile(reservation, actual if metered else None, uncertain=not metered)
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
