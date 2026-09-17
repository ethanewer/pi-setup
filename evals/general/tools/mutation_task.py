#!/usr/bin/env python3
"""Execute semantic wrong-solution controls for one sealed candidate."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import uuid

import _toml_compat
from generate_tasks import seal, verify_seal, verify_record


def mutations(queue, ident, timeout=600):
    with queue.connect() as db:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
    if job is None or job['state'] != 'needs_review':
        raise ValueError('mutations require a QA-checked draft')
    draft = json.loads(job['result'])
    source = Path(draft['bundle'])
    verify_record(queue, source)
    task = source / 'workspace/tasks' / ident
    manifest_path = task / 'tests/mutations/manifest.json'
    manifest = json.loads(manifest_path.read_text())
    cases = manifest.get('mutations') if isinstance(manifest, dict) else None
    if not isinstance(cases, list) or len(cases) < 3:
        raise ValueError('at least three semantic mutations are required')
    kinds, digests = set(), set()
    for case in cases:
        if not isinstance(case, dict) or not all(case.get(k) for k in ('name', 'kind', 'script', 'intended_reason')):
            raise ValueError('each mutation requires name, kind, script, and intended_reason')
        script = task / 'tests/mutations' / case['script']
        if not script.resolve().is_relative_to((task / 'tests/mutations').resolve()) or script.is_symlink():
            raise ValueError('invalid mutation script path')
        digest = hashlib.sha256(script.read_bytes()).hexdigest()
        if digest in digests or case['kind'] in kinds:
            raise ValueError('mutations must be distinct in kind and implementation')
        digests.add(digest)
        kinds.add(case['kind'])
    config = _toml_compat.loads((task / 'task.toml').read_text())
    trial = uuid.uuid4().hex
    output = queue.path.parent / 'mutations' / ident / trial
    output.mkdir(parents=True)
    image = 'general-mutation-' + trial
    result = {'kind': 'semantic_mutations', 'job': ident, 'bundle': str(output),
              'fingerprint': draft['fingerprint'], 'cases': []}
    claim = queue.control.claim_stage(job['candidate_id'], 'mutation',
                                      max(120, timeout * (len(cases) + 1) + 120))
    try:
        with (output / 'build.log').open('w') as log:
            subprocess.run(['docker', 'build', '-t', image, str(task / 'environment')],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=timeout)
        for number, case in enumerate(cases):
            case_output = output / f'case-{number}'
            case_output.mkdir()
            name = image + '-' + str(number)
            command = ['docker', 'run', '--name', name, '--network', 'none',
                       '--cpus', str(config['environment'].get('cpus', 1)),
                       '--memory', str(config['environment'].get('memory_mb', 4096)) + 'm',
                       '--mount', f'type=bind,source={(task / "tests").resolve()},target=/tests,readonly',
                       '--mount', f'type=bind,source={case_output.resolve()},target=/logs/verifier',
                       image, '/bin/bash', '-c',
                       f'bash /tests/mutations/{case["script"]} && bash /tests/test.sh']
            with (case_output / 'run.log').open('w') as log:
                ran = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
            subprocess.run(['docker', 'rm', '--force', name], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
            rewards = list(case_output.rglob('reward.txt'))
            reward = rewards[0].read_text().strip() if len(rewards) == 1 else None
            diagnostics = (case_output / 'run.log').read_text(errors='replace')
            reason_seen = re.search(case['intended_reason'], diagnostics, re.I) is not None
            passed = ran.returncode == 0 and reward in ('0', '0.0') and reason_seen
            result['cases'].append({**case, 'reward': reward, 'returncode': ran.returncode,
                                    'intended_reason_observed': reason_seen, 'passed': passed})
        if not all(case['passed'] for case in result['cases']):
            raise ValueError('one or more mutations did not fail for the intended behavioral reason')
        verify_record(queue, source)
        result['status'] = 'passed'
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        result.update(status='failed', error=str(exc))
    finally:
        subprocess.run(['docker', 'image', 'rm', image], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=30)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    result['seal_sha256'] = verify_seal(output)
    queue.control.account_storage(output, job['candidate_id'])
    with queue.connect() as db:
        db.execute('INSERT INTO checks VALUES(?,?,?)', (trial, ident, json.dumps(result)))
    queue.control.finish_stage(claim, 'passed' if result['status'] == 'passed' else 'failed', result)
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'passed' else 1
