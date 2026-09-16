"""Bounded common QA orchestration. Release remains an explicit reviewed action."""
import concurrent.futures
import json
import uuid

from generate_tasks import independent_review, recheck, seal, verify_seal
from pilot_task import pilot
from qa_batch import audit


def qualify(queue, reference_root, max_jobs=3, workers=1, trials=2, timeout=600):
    if not 1 <= workers <= 4 or max_jobs < 1 or not 1 <= trials <= 3 or timeout < 1:
        raise ValueError('invalid qualification limits')
    with queue.connect() as db:
        jobs = db.execute("SELECT id,result FROM jobs WHERE state='needs_review' ORDER BY id LIMIT ?", (max_jobs,)).fetchall()
    ids = [job['id'] for job in jobs]
    fingerprints = {job['id']: json.loads(job['result']).get('fingerprint') for job in jobs}
    if not ids:
        raise ValueError('no QA-checked drafts to qualify')

    def one(ident):
        result = {'job': ident, 'fingerprint': fingerprints[ident], 'status': 'held', 'stage': 'design_review'}

        def unchanged():
            with queue.connect() as db:
                current = db.execute('SELECT state,result FROM jobs WHERE id=?', (ident,)).fetchone()
            if current['state'] != 'needs_review' or json.loads(current['result']).get('fingerprint') != fingerprints[ident]:
                raise ValueError('candidate changed during qualification')

        try:
            unchanged()
            if independent_review(queue, ident, timeout):
                return result
            with queue.connect() as db:
                row = db.execute('SELECT result FROM reviews WHERE job=? ORDER BY rowid DESC LIMIT 1', (ident,)).fetchone()
            review = json.loads(row['result'])
            if review.get('error') or review['review']['verdict'] != 'pass':
                result['reason'] = 'design review requires revision; pilots skipped'
                return result
            if review.get('author_fingerprint') != fingerprints[ident]:
                raise ValueError('review refers to a different candidate revision')
            unchanged()
            result['stage'] = 'repeat_runtime'
            if recheck(queue, ident):
                return result
            result['stage'] = 'blind_pilots'
            for _ in range(trials):
                unchanged()
                if pilot(queue, ident, timeout):
                    return result
            unchanged()
            result.update(status='evidence_collected', stage='release_review',
                          reason='not accepted: adjudicate mutations, source, diversity and difficulty evidence')
            return result
        except (OSError, ValueError, RuntimeError) as exc:
            result['error'] = str(exc)
            return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(one, ids))
    audit_error = None
    try:
        audit_code = audit(queue, reference_root, ids)
    except (OSError, ValueError, RuntimeError) as exc:
        audit_code, audit_error = 1, str(exc)
    summary = {'jobs': results, 'contamination_clear': audit_code == 0,
               'accepted': 0, 'automatic_promotion': False, 'audit_error': audit_error,
               'kind': 'qualification', 'usage': {}}
    ident = uuid.uuid4().hex
    output = queue.path.parent / 'qualification' / ident
    output.mkdir(parents=True)
    summary['bundle'] = str(output)
    (output / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    summary['seal_sha256'] = verify_seal(output)
    with queue.connect() as db:
        db.execute('INSERT INTO checks VALUES(?,?,?)', (ident, '*', json.dumps(summary)))
    print(json.dumps(summary, indent=2))
    return 0 if audit_code == 0 and all(r['status'] == 'evidence_collected' for r in results) else 1
