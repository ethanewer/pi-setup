"""Run contamination QA on sealed queue drafts, outside authoring contexts."""
import json
from pathlib import Path
import sys
import threading
import uuid

from generate_tasks import ROOT, run_process, seal, verify_seal, verify_record


def audit(queue, reference_root, ids=None):
    with queue.connect() as db:
        rows = db.execute("SELECT * FROM jobs WHERE state='needs_review' ORDER BY id").fetchall()
    if ids is not None:
        rows = [row for row in rows if row['id'] in ids]
        if {row['id'] for row in rows} != set(ids):
            raise ValueError('some selected candidates are no longer QA-checked drafts')
    if not rows:
        raise ValueError('no QA-checked drafts to audit')
    ident = uuid.uuid4().hex
    output = queue.path.parent / 'contamination' / ident
    output.mkdir(parents=True)
    command = [sys.executable, str(ROOT / 'qa/audit_candidates.py'),
               '--reference-root', str(reference_root.resolve()), '--output', str(output / 'audit')]
    bundles = []
    fingerprints = {}
    stage_claims = []
    for row in rows:
        draft = json.loads(row['result'])
        bundle = Path(draft['bundle'])
        verify_record(queue, bundle)
        bundles.append(bundle)
        fingerprints[row['id']] = draft['fingerprint']
        stage_claims.append(queue.control.claim_stage(row['candidate_id'], 'audit', 1920))
        command += ['--candidate', str(bundle / 'workspace/candidate.json'),
                    '--suite-root', str(bundle / 'workspace')]
    result = {'kind': 'contamination', 'bundle': str(output), 'fingerprints': fingerprints, 'usage': {}}
    try:
        code = run_process(command, output, output / 'audit.log', output / 'stderr.log', 1800, threading.Event())
        result['status'] = 'clear' if code == 0 else 'needs_review'
        result['returncode'] = code
        for bundle in bundles:
            verify_record(queue, bundle)
    except (OSError, ValueError, TimeoutError) as exc:
        result.update(status='failed', error=str(exc))
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    result['seal_sha256'] = verify_seal(output)
    for row in rows:
        queue.control.account_storage(output, row['candidate_id'])
    with queue.connect() as db:
        db.execute('INSERT INTO checks VALUES(?,?,?)', (ident, '*', json.dumps(result)))
    for claim in stage_claims:
        queue.control.finish_stage(claim, 'passed' if result['status'] == 'clear' else 'failed', result)
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'clear' else 1
