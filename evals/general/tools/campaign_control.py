#!/usr/bin/env python3
"""Durable campaign-wide admission, stage, budget, and promotion controls.

This module deliberately contains no model or Docker calls.  It is the small,
trusted coordinator used by local workers.  SQLite must live on one local host;
workers exchange immutable bundle paths and fenced tokens through this ledger.
"""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import time
import uuid


STAGES = ('author', 'review', 'build', 'mutation', 'repeat_runtime', 'pilot',
          'audit', 'promotion')
PAID_STAGES = ('author', 'review', 'pilot')
LANE_TARGETS = {'skills': 700, 'repo': 700, 'pr-issue': 600}


def stable_json(value) -> str:
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def normalized_text(value: str) -> str:
    return ' '.join(re.findall(r'[a-z0-9]+', value.lower()))


def identity_digest(identity: dict) -> str:
    """Hash an already-normalized source/workflow identity."""
    return hashlib.sha256(stable_json(identity).encode()).hexdigest()


def validate_identity(identity: dict, canonical_repository) -> dict:
    if not isinstance(identity, dict):
        raise ValueError('source identity must be an object')
    lane = identity.get('lane')
    if lane not in ('skills', 'repo', 'pr-issue'):
        raise ValueError('source identity has invalid lane')
    revision = str(identity.get('revision', '')).lower()
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('source identity requires a pinned 40-hex revision')
    workflow = identity.get('workflow')
    if not isinstance(workflow, dict) or not workflow.get('outcome'):
        raise ValueError('source identity requires an approved workflow object and outcome')
    required = ('decisions', 'deliverables', 'failure_modes', 'distinguishers',
                'test_structure', 'skill_coverage')
    for key in required:
        if not isinstance(workflow.get(key), list) or not workflow[key]:
            raise ValueError(f'workflow.{key} must be a nonempty list')
    reference = identity.get('reference')
    skill_hash = identity.get('skill_hash')
    if lane == 'pr-issue' and not isinstance(reference, str):
        raise ValueError('PR/issue identities require reference')
    if lane == 'skills' and not re.fullmatch(r'[0-9a-f]{64}', str(skill_hash or '')):
        raise ValueError('skills identities require a SHA256 skill_hash')
    skill_artifact = str(identity.get('skill_artifact') or '')
    if lane == 'skills' and not skill_artifact:
        raise ValueError('skills identities require an immutable skill_artifact receipt')
    for key in ('family', 'language', 'domain', 'license'):
        if not isinstance(identity.get(key), str) or not identity[key].strip():
            raise ValueError(f'source identity requires {key}')
    return {
        'lane': lane,
        'repository': canonical_repository(identity['repository']),
        'revision': revision,
        'reference': normalized_text(reference or ''),
        'skill_hash': str(skill_hash or '').lower(),
        'skill_artifact': skill_artifact,
        'family': normalized_text(identity['family']),
        'language': normalized_text(identity['language']),
        'domain': normalized_text(identity['domain']),
        'license': identity['license'].strip(),
        'workflow': {
            'outcome': normalized_text(str(workflow['outcome'])),
            **{key: sorted({normalized_text(str(v)) for v in workflow[key]})
               for key in required},
        },
    }


def semantic_facets(identity: dict) -> set[str]:
    """Return declared meaning-bearing facets, not instruction word shingles.

    Admission requires authors to describe decisions, outputs, failure modes,
    skill coverage, and test shape.  Comparing those structured facets catches
    renamed/parameter-swapped workflows that a surface text comparison misses.
    """
    workflow = identity['workflow']
    result = {f'outcome:{workflow["outcome"]}'}
    for key in ('decisions', 'deliverables', 'failure_modes', 'distinguishers',
                'test_structure', 'skill_coverage'):
        result.update(f'{key}:{value}' for value in workflow[key])
    return result


class CampaignControl:
    def __init__(self, path: Path, canonical_repository):
        self.path = Path(path).resolve()
        self.canonical_repository = canonical_repository

    @contextmanager
    def connect(self):
        db = sqlite3.connect(str(self.path), timeout=30)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def admit(self, identity: dict, task_id: str, max_attempts: int = 3,
              candidate_id: str | None = None) -> str:
        identity = validate_identity(identity, self.canonical_repository)
        candidate_id = candidate_id or 'cand-' + uuid.uuid4().hex
        if not re.fullmatch(r'cand-[0-9a-f]{32}', candidate_id):
            raise ValueError('candidate_id must be an immutable cand- UUID')
        source_key = identity_digest({k: v for k, v in identity.items() if k != 'workflow'})
        workflow_key = identity_digest(identity)
        facets = semantic_facets(identity)
        now = time.time()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            reason = None
            exact = db.execute('SELECT candidate_id FROM admissions WHERE workflow_key=? AND decision="admitted"',
                               (workflow_key,)).fetchone()
            if exact:
                reason = 'duplicate source/workflow identity: ' + exact['candidate_id']
            if reason is None:
                for row in db.execute('SELECT candidate_id,identity_json FROM admissions WHERE decision="admitted"'):
                    other = json.loads(row['identity_json'])
                    overlap = facets & semantic_facets(other)
                    # Same practical outcome plus two structured facets is a
                    # duplicate even if prose and task names differ.
                    same_outcome = identity['workflow']['outcome'] == other['workflow']['outcome']
                    same_shape = len(overlap - {f'outcome:{identity["workflow"]["outcome"]}'}) >= 2
                    same_source = source_key == identity_digest({k: v for k, v in other.items() if k != 'workflow'})
                    if (same_outcome and same_shape) or (same_source and same_shape):
                        reason = f'semantic workflow duplicate of {row["candidate_id"]}'
                        break
            admitted = [json.loads(r['identity_json']) for r in db.execute(
                'SELECT identity_json FROM admissions WHERE decision="admitted"')]
            if reason is None and len(admitted) >= 6000:
                reason = 'campaign candidate admission cap reached'
            if reason is None and sum(x.get('repository') == identity['repository'] for x in admitted) >= 10:
                reason = 'repository concentration cap reached'
            if reason is None and sum(x.get('family') == identity['family'] for x in admitted) >= 40:
                reason = 'scenario-family concentration cap reached'
            projected_total = len(admitted) + 1
            projected_language = sum(x.get('language') == identity['language'] for x in admitted) + 1
            if reason is None and projected_total >= 20 and projected_language / projected_total > .45:
                reason = 'language concentration cap would be exceeded'
            decision = 'rejected' if reason else 'admitted'
            try:
                db.execute('''INSERT INTO admissions
                    (candidate_id,task_id,source_key,workflow_key,identity_json,decision,reason,created)
                    VALUES(?,?,?,?,?,?,?,?)''',
                    (candidate_id, task_id, source_key, workflow_key, stable_json(identity),
                     decision, reason, now))
            except sqlite3.IntegrityError:
                # Keep a durable record of repeated rejected attempts under a
                # fresh immutable candidate id; never rename it into admission.
                raise
            if not reason:
                db.execute('''INSERT INTO jobs
                    (id,candidate_id,task_id,lane,repository,source_key,workflow_key,
                     source_identity,state,attempt,max_attempts)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
                    (task_id, candidate_id, task_id, identity['lane'], identity['repository'],
                     source_key, workflow_key, stable_json(identity), 'queued', 0, max_attempts))
        if reason:
            raise ValueError(reason)
        return candidate_id

    def configure(self, *, dollar_cap: float, author_calls: int, reviewer_calls: int,
                  pilot_calls: int, fleet_concurrency: int, storage_bytes: int,
                  approved_by: str, policy_version: str, isolation_receipt: dict) -> None:
        if min(dollar_cap, author_calls, reviewer_calls, pilot_calls,
               fleet_concurrency, storage_bytes) <= 0 or not approved_by or not policy_version:
            raise ValueError('all campaign limits and approval fields are required')
        if author_calls > 18000:
            raise ValueError('author/repair call limit exceeds campaign outer cap')
        isolation_fields = ('dedicated_disposable_workers', 'scoped_credentials',
                            'bounded_storage', 'restricted_host_reads',
                            'controlled_egress', 'no_shared_host_docker')
        if not isinstance(isolation_receipt, dict) or any(isolation_receipt.get(k) is not True
                                                          for k in isolation_fields):
            raise ValueError('isolation receipt does not satisfy production worker policy')
        config = locals().copy()
        config.pop('self')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM campaign_config').fetchone():
                raise ValueError('campaign configuration is immutable once approved')
            db.execute('INSERT INTO campaign_config(config_json,created) VALUES(?,?)',
                       (stable_json(config), time.time()))

    def reserve(self, stage: str, candidate_id: str, estimated_dollars: float,
                call_count: int = 1) -> str:
        if stage not in STAGES or estimated_dollars < 0 or call_count < 0:
            raise ValueError('invalid reservation')
        token = uuid.uuid4().hex
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT config_json FROM campaign_config').fetchone()
            if row is None:
                raise ValueError('campaign budget has not been approved')
            config = json.loads(row['config_json'])
            used = db.execute('''SELECT COALESCE(SUM(COALESCE(actual_dollars,reserved_dollars)),0) cost
                              FROM budget_reservations WHERE state IN ('reserved','reconciled','uncertain')''').fetchone()['cost']
            if used + estimated_dollars > config['dollar_cap']:
                raise ValueError('fleet-wide dollar cap exhausted')
            column = {'author': 'author_calls', 'review': 'reviewer_calls', 'pilot': 'pilot_calls'}.get(stage)
            if column:
                calls = db.execute('SELECT COALESCE(SUM(call_count),0) n FROM budget_reservations WHERE stage=?',
                                   (stage,)).fetchone()['n']
                if calls + call_count > config[column]:
                    raise ValueError(f'fleet-wide {stage} call cap exhausted')
            active = db.execute("SELECT COUNT(DISTINCT candidate_id) n FROM stage_attempts WHERE state='running'").fetchone()['n']
            already_active = db.execute(
                "SELECT 1 FROM stage_attempts WHERE state='running' AND candidate_id=? LIMIT 1",
                (candidate_id,)).fetchone()
            if not already_active and active >= config['fleet_concurrency']:
                raise ValueError('fleet-wide concurrency cap reached')
            db.execute('''INSERT INTO budget_reservations
                (token,candidate_id,stage,reserved_dollars,call_count,state,created)
                VALUES(?,?,?,?,?,'reserved',?)''',
                (token, candidate_id, stage, estimated_dollars, call_count, time.time()))
        return token

    def reconcile(self, token: str, actual_dollars: float | None, uncertain=False) -> None:
        with self.connect() as db:
            changed = db.execute('''UPDATE budget_reservations SET actual_dollars=?,state=?,finished=?
                                  WHERE token=? AND state='reserved' ''',
                                 (actual_dollars, 'uncertain' if uncertain else 'reconciled',
                                  time.time(), token)).rowcount
            if changed != 1:
                raise ValueError('reservation is missing or already reconciled')

    def account_storage(self, path: Path, candidate_id: str) -> int:
        path = Path(path).resolve()
        size = sum(item.stat().st_size for item in path.rglob('*')
                   if item.is_file() and not item.is_symlink())
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            config = db.execute('SELECT config_json FROM campaign_config').fetchone()
            if config is None:
                return size
            cap = json.loads(config['config_json'])['storage_bytes']
            old = db.execute('SELECT bytes FROM storage_objects WHERE path=?', (str(path),)).fetchone()
            used = db.execute('SELECT COALESCE(SUM(bytes),0) n FROM storage_objects').fetchone()['n']
            if used - (old['bytes'] if old else 0) + size > cap:
                raise ValueError('campaign durable-storage cap exhausted')
            db.execute('''INSERT INTO storage_objects VALUES(?,?,?,?)
                        ON CONFLICT(path) DO UPDATE SET bytes=excluded.bytes,recorded=excluded.recorded''',
                       (str(path), candidate_id, size, time.time()))
        return size

    def claim_stage(self, candidate_id: str, stage: str, lease_seconds=120,
                    reservation: str | None = None) -> dict:
        if stage not in STAGES:
            raise ValueError('invalid stage')
        now, token = time.time(), uuid.uuid4().hex
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute("UPDATE stage_attempts SET state='lease_expired',finished=? WHERE state='running' AND lease<?",
                       (now, now))
            config = db.execute('SELECT config_json FROM campaign_config').fetchone()
            if config:
                limit = json.loads(config['config_json'])['fleet_concurrency']
                active = db.execute("SELECT COUNT(DISTINCT candidate_id) n FROM stage_attempts WHERE state='running'").fetchone()['n']
                already_active = db.execute(
                    "SELECT 1 FROM stage_attempts WHERE state='running' AND candidate_id=? LIMIT 1",
                    (candidate_id,)).fetchone()
                if not already_active and active >= limit:
                    raise ValueError('fleet-wide concurrency cap reached')
            if db.execute("SELECT 1 FROM stage_attempts WHERE candidate_id=? AND stage=? AND state='running'",
                          (candidate_id, stage)).fetchone():
                raise ValueError('stage already running')
            number = db.execute('SELECT COALESCE(MAX(number),0)+1 n FROM stage_attempts WHERE candidate_id=? AND stage=?',
                                (candidate_id, stage)).fetchone()['n']
            db.execute('''INSERT INTO stage_attempts
                (candidate_id,stage,number,token,reservation_token,started,lease,state)
                VALUES(?,?,?,?,?,?,?,'running')''',
                (candidate_id, stage, number, token, reservation, now, now + lease_seconds))
        return {'candidate_id': candidate_id, 'stage': stage, 'number': number,
                'token': token, 'lease': now + lease_seconds}

    def heartbeat_stage(self, claim: dict, lease_seconds=120) -> bool:
        now = time.time()
        with self.connect() as db:
            return db.execute('''UPDATE stage_attempts SET lease=? WHERE token=? AND state='running' AND lease>=?''',
                              (now + lease_seconds, claim['token'], now)).rowcount == 1

    def finish_stage(self, claim: dict, state: str, result: dict) -> None:
        if state not in ('passed', 'failed', 'held'):
            raise ValueError('invalid final stage state')
        now = time.time()
        with self.connect() as db:
            changed = db.execute('''UPDATE stage_attempts SET state=?,result=?,finished=?
                                  WHERE token=? AND state='running' AND lease>=?''',
                                 (state, stable_json(result), now, claim['token'], now)).rowcount
            if changed != 1:
                raise RuntimeError('stage lease lost; refusing stale result')

    def recover_killed_stage(self, token: str, reason: str) -> None:
        """Fence a confirmed-dead worker while retaining uncertain spend."""
        if not reason.strip():
            raise ValueError('recovery reason is required')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute("SELECT reservation_token FROM stage_attempts WHERE token=? AND state='running'",
                             (token,)).fetchone()
            if row is None:
                raise ValueError('stage is not recoverable')
            db.execute("UPDATE stage_attempts SET state='failed',finished=?,result=? WHERE token=? AND state='running'",
                       (time.time(), stable_json({'error': reason, 'operator_recovery': True}), token))
            if row['reservation_token']:
                db.execute("UPDATE budget_reservations SET state='uncertain',finished=? WHERE token=? AND state='reserved'",
                           (time.time(), row['reservation_token']))

    def mark_charge_uncertain(self, token: str, reason: str) -> None:
        if not reason.strip():
            raise ValueError('accounting correction reason is required')
        with self.connect() as db:
            changed = db.execute("UPDATE budget_reservations SET state='uncertain',actual_dollars=NULL,finished=? WHERE token=?",
                                 (time.time(), token)).rowcount
            if changed != 1:
                raise ValueError('unknown reservation')
            db.execute('INSERT INTO operator_events VALUES(?,?,?)',
                       (time.time(), token, 'mark_charge_uncertain: ' + reason))

    def correct_charge(self, token: str, actual_dollars: float, reason: str) -> None:
        """Auditably correct a reconciled charge after a pricing-rule fix."""
        if actual_dollars < 0 or not reason.strip():
            raise ValueError('a nonnegative charge and correction reason are required')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute(
                "SELECT actual_dollars FROM budget_reservations WHERE token=? AND state='reconciled'",
                (token,)).fetchone()
            if row is None:
                raise ValueError('only a reconciled reservation can be corrected')
            db.execute('UPDATE budget_reservations SET actual_dollars=?,finished=? WHERE token=?',
                       (actual_dollars, time.time(), token))
            db.execute('INSERT INTO operator_events VALUES(?,?,?)',
                       (time.time(), token,
                        f'correct_charge: {row["actual_dollars"]} -> {actual_dollars}: {reason}'))

    def promote(self, candidate_id: str, fingerprint: str, policy_version: str,
                approval: dict, manifest_path: Path) -> bool:
        """Idempotently append one approved fingerprint to a release manifest."""
        if not re.fullmatch(r'[0-9a-f]{64}', fingerprint):
            raise ValueError('invalid final fingerprint')
        claim = self.claim_stage(candidate_id, 'promotion', 300)
        was_new = False
        with self.connect() as db:
            db.execute('BEGIN EXCLUSIVE')
            config_row = db.execute('SELECT config_json FROM campaign_config').fetchone()
            if config_row is None or json.loads(config_row['config_json'])['policy_version'] != policy_version:
                raise ValueError('QA policy version is not the approved campaign policy')
            job = db.execute('SELECT task_id,lane FROM jobs WHERE candidate_id=?', (candidate_id,)).fetchone()
            if job is None:
                raise ValueError('unknown candidate')
            existing = db.execute('SELECT fingerprint FROM promotions WHERE candidate_id=?', (candidate_id,)).fetchone()
            if existing:
                if existing['fingerprint'] != fingerprint:
                    raise ValueError('candidate was already promoted with different bytes')
            else:
                if not approval.get('independent_reviewer') or approval.get('status') != 'approved':
                    raise ValueError('independent release approval required')
                required = {'review', 'mutation', 'repeat_runtime', 'pilot', 'audit'}
                passed = set()
                for row in db.execute("SELECT stage,result FROM stage_attempts WHERE candidate_id=? AND state='passed'",
                                      (candidate_id,)):
                    evidence = json.loads(row['result'] or '{}')
                    bound = (evidence.get('fingerprint') == fingerprint
                             or evidence.get('author_fingerprint') == fingerprint
                             or evidence.get('fingerprints', {}).get(job['task_id']) == fingerprint)
                    if bound:
                        passed.add(row['stage'])
                if not required <= passed:
                    raise ValueError('required fingerprint-bound stages have not passed: ' +
                                     ','.join(sorted(required - passed)))
                db.execute('INSERT INTO promotions VALUES(?,?,?,?,?,?)',
                           (candidate_id, job['task_id'], fingerprint, policy_version,
                            stable_json(approval), time.time()))
                promoted_lane = db.execute('''SELECT COUNT(*) n FROM promotions p
                    JOIN jobs j ON j.candidate_id=p.candidate_id WHERE j.lane=?''',
                                           (job['lane'],)).fetchone()['n']
                if promoted_lane > LANE_TARGETS[job['lane']]:
                    raise ValueError('lane accepted-task target already complete')
                was_new = True
            rows = [dict(row) for row in db.execute('SELECT candidate_id,task_id,fingerprint,policy_version,approval_json,created FROM promotions ORDER BY created')]
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = manifest_path.with_suffix(manifest_path.suffix + '.tmp')
            temporary.write_text(json.dumps(rows, indent=2) + '\n')
            temporary.replace(manifest_path)
        self.finish_stage(claim, 'passed', {'fingerprint': fingerprint,
                                           'policy_version': policy_version,
                                           'idempotent_retry': not was_new})
        return was_new
