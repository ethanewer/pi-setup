#!/usr/bin/env python3
"""Run one isolated, budgeted Luna source-planning call."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import threading

from campaign_control import validate_identity
from generate_tasks import (EFFORT, MODEL, Queue, canonical_repository, luna_usage_cost,
                            run_process, seal, session_context, usage_from_events, verify_seal)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--prompt', type=Path, required=True)
    parser.add_argument('--reserve-dollars', type=float, required=True)
    parser.add_argument('--timeout', type=int, default=1800)
    args = parser.parse_args()
    queue = Queue(args.db)
    ident = 'source-plan-' + hashlib.sha256(args.prompt.read_bytes()).hexdigest()[:16]
    reservation = queue.control.reserve('author', ident, args.reserve_dollars)
    claim = queue.control.claim_stage(ident, 'author', args.timeout + 120, reservation)
    output, work = args.workspace.resolve(), args.workspace.resolve() / 'workspace'
    work.mkdir(parents=True, exist_ok=False)
    (work / 'prompt.txt').write_bytes(args.prompt.read_bytes())
    result = {'kind': 'source_plan', 'candidate_id': ident, 'bundle': str(output),
              'model': MODEL, 'reasoning_effort': EFFORT}
    try:
        with (work / 'prompt.txt').open() as source:
            code = run_process(['codex', '-a', 'never', 'exec', '--ignore-user-config',
                '-m', MODEL, '-c', 'model_reasoning_effort="medium"', '-s', 'workspace-write',
                '-c', 'sandbox_workspace_write.network_access=true', '--skip-git-repo-check',
                '-C', str(work), '--json', '-o', str(work / 'final.txt'), '-'], work,
                output / 'events.jsonl', output / 'stderr.log', args.timeout,
                threading.Event(), source)
        if code:
            raise ValueError(f'source planner exited {code}')
        raw = json.loads((work / 'plan.json').read_text())
        identities = raw.get('identities') if isinstance(raw, dict) else None
        if not isinstance(identities, list) or len(identities) != 8:
            raise ValueError('plan.json must contain exactly 8 identities')
        identities = [validate_identity(value, canonical_repository) for value in identities]
        (work / 'plan.json').write_text(json.dumps({'identities': identities}, indent=2) + '\n')
        result.update(status='passed', identity_count=8)
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
