#!/usr/bin/env python3
"""Blind offline pilots for reviewed batch drafts; never an acceptance decision."""
import json
from pathlib import Path
import shutil
import subprocess
import threading
import uuid

import _toml_compat
from generate_tasks import (MODEL, EFFORT, luna_usage_cost, run_process, usage_from_events,
                            seal, verify_seal, verify_record, session_context)


def pilot(queue, ident, timeout=600, reserve_dollars=None):
    with queue.connect() as db:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
    if job is None or job['state'] != 'needs_review':
        raise ValueError('pilot requires a QA-checked draft')
    draft = json.loads(job['result'])
    bundle = Path(draft['bundle'])
    verify_record(queue, bundle)
    reservation = None
    if queue.configured():
        if reserve_dollars is None:
            raise ValueError('pilot requires an approved dollar reservation')
        reservation = queue.control.reserve('pilot', job['candidate_id'], reserve_dollars)
    stage_claim = queue.control.claim_stage(job['candidate_id'], 'pilot',
                                            max(120, timeout + 1500), reservation)
    task = bundle / 'workspace/tasks' / ident
    config = _toml_compat.loads((task / 'task.toml').read_text())
    if config['environment'].get('network_mode') != 'no-network':
        raise ValueError('pilot requires an offline task')
    trial = uuid.uuid4().hex
    output = queue.path.parent / 'pilots' / ident / trial
    work = output / 'workspace'
    work.mkdir(parents=True)
    verifier = output / 'verifier'
    verifier.mkdir()
    image = 'general-pilot-' + trial
    container = image
    result = {'kind': 'blind_pilot', 'bundle': str(output), 'job': ident,
              'fingerprint': draft['fingerprint'], 'model': MODEL, 'reasoning_effort': EFFORT,
              'author_seal': draft['seal_sha256'], 'network': 'none'}
    try:
        with (output / 'build.log').open('w') as log:
            subprocess.run(['docker', 'build', '-t', image, str(task / 'environment')],
                           stdout=log, stderr=subprocess.STDOUT, timeout=600, check=True)
        result['image_id'] = subprocess.check_output(['docker', 'image', 'inspect', image, '--format', '{{.Id}}'], text=True).strip()
        subprocess.run(['docker', 'run', '-d', '--name', container, '--network', 'none',
                        '--cpus', str(config['environment'].get('cpus', 1)),
                        '--memory', str(config['environment'].get('memory_mb', 4096)) + 'm',
                        '--mount', f'type=bind,source={verifier},target=/logs/verifier',
                        image, 'sleep', 'infinity'], check=True, stdout=subprocess.DEVNULL, timeout=30)
        # No candidate, receipts, oracle, verifier, or author conversation enters this context.
        shutil.copy2(task / 'instruction.md', work / 'instruction.md')
        prompt = f'''Solve the task described in instruction.md inside the already running offline container {container}.
Use docker exec {container} ... to inspect and modify /app. You may copy your own files into that container.
Do not inspect host files outside this workspace, other containers, images, QA files or hidden tests.
Do not change networking, container configuration or mounts. Do not stop/remove the container.
The task will be graded after you finish. Deliver all requested work inside the container.
'''
        (work / 'prompt.txt').write_text(prompt)
        with (work / 'prompt.txt').open() as source:
            code = run_process(['codex', '-a', 'never', 'exec', '--ignore-user-config', '-m', MODEL,
                                '-c', 'model_reasoning_effort="medium"', '-s', 'danger-full-access',
                                '--skip-git-repo-check', '-C', str(work), '--json',
                                '-o', str(work / 'final.txt'), '-'], work,
                               output / 'events.jsonl', output / 'stderr.log', timeout, threading.Event(), source)
        if code:
            raise ValueError(f'pilot CLI exited {code}')
        # Tests become available only after the agent session has ended.
        subprocess.run(['docker', 'cp', str(task / 'tests'), container + ':/tests'], check=True, timeout=30)
        with (output / 'verifier.log').open('w') as log:
            checked = subprocess.run(['docker', 'exec', container, 'bash', '/tests/test.sh'],
                                     stdout=log, stderr=subprocess.STDOUT, timeout=600)
        result['verifier_returncode'] = checked.returncode
        rewards = list(verifier.rglob('reward.txt'))
        reward = rewards[0].read_text().strip() if len(rewards) == 1 else None
        if reward not in ('0', '0.0', '1', '1.0'):
            raise ValueError('missing or nonbinary pilot reward')
        result['reward'] = int(float(reward))
        result['status'] = 'measured'
        with (output / 'deliverables.log').open('w') as log:
            for number, path in enumerate(config.get('metadata', {}).get('deliverables', [])):
                if not path.startswith('/app/') or '..' in Path(path).parts:
                    continue
                subprocess.run(['docker', 'cp', container + ':' + path, str(output / f'deliverable-{number}')],
                               stdout=log, stderr=subprocess.STDOUT, timeout=30)
        verify_record(queue, bundle)
    except (OSError, ValueError, TimeoutError, subprocess.SubprocessError) as exc:
        result.update(status='failed', error=str(exc))
    finally:
        for command in (['docker', 'rm', '--force', container], ['docker', 'image', 'rm', image]):
            try:
                subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            except (OSError, subprocess.SubprocessError):
                result['cleanup_error'] = f'Inspect exact resources: {container}, {image}'
    result['usage'], result['thread_id'] = usage_from_events(output / 'events.jsonl')
    try:
        result['session_context'] = session_context(result['thread_id'])
    except ValueError as exc:
        result.update(status='failed', error=str(exc))
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    result['seal_sha256'] = verify_seal(output)
    queue.control.account_storage(output, job['candidate_id'])
    with queue.connect() as db:
        db.execute('INSERT INTO checks VALUES(?,?,?)', (trial, ident, json.dumps(result)))
    queue.control.finish_stage(stage_claim, 'failed' if result.get('error') else 'passed', result)
    if reservation:
        if result['usage']:
            queue.control.reconcile(reservation, luna_usage_cost(result['usage']))
        else:
            queue.control.mark_charge_uncertain(
                reservation, 'completed pilot has no parseable usage event')
    print(json.dumps(result, indent=2))
    return 1 if result.get('error') else 0
