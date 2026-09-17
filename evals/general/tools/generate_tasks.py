#!/usr/bin/env python3
"""Bounded, resumable authoring queue. Drafts never enter the live registry."""
import argparse
import concurrent.futures
from contextlib import contextmanager
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import threading
import time
import uuid
from urllib.parse import urlsplit

from author_task import validate, fingerprint
from lint_tasks import CATEGORIES, RUBRIC_KEYS
from campaign_control import CampaignControl, normalized_text, stable_json

ROOT = Path(__file__).resolve().parents[1]
MODEL = 'gpt-5.6-luna'
EFFORT = 'medium'
LANES = ('skills', 'repo', 'pr-issue')


def directory_file_bytes(root):
    """Count regular-file bytes while tolerating concurrently removed scratch."""
    total = 0
    for directory, _subdirectories, filenames in os.walk(
            root, topdown=True, followlinks=False, onerror=lambda _error: None):
        for filename in filenames:
            try:
                metadata = os.stat(Path(directory) / filename, follow_symlinks=False)
            except (FileNotFoundError, NotADirectoryError):
                continue
            if stat.S_ISREG(metadata.st_mode):
                total += metadata.st_size
    return total


def canonical_repository(url):
    parsed = urlsplit(url.strip())
    parts = parsed.path.strip('/').removesuffix('.git').split('/')
    if (parsed.scheme != 'https' or parsed.netloc.lower() != 'github.com'
            or parsed.query or parsed.fragment or len(parts) != 2
            or not all(re.fullmatch(r'[A-Za-z0-9_.-]+', p) and p not in ('.', '..') for p in parts)):
        raise ValueError('expected an HTTPS GitHub repository URL')
    return 'https://github.com/' + '/'.join(parts).lower()


def sources(path):
    result = {}
    with path.open(newline='', encoding='utf-8-sig') as stream:
        reader = csv.DictReader(stream)
        if not {'name', 'github_url'} <= set(reader.fieldnames or []):
            raise ValueError('CSV requires name,github_url')
        for row in reader:
            if row['github_url'].strip():
                url = canonical_repository(row['github_url'])
                result.setdefault(url, row['name'].strip())
    return result


def normalize_candidate(candidate, job):
    """Queue-owned identity is mechanical metadata, not a model recall test."""
    if not isinstance(candidate, dict):
        raise ValueError('candidate must be an object')
    candidate = json.loads(json.dumps(candidate))
    admitted = not json.loads(job.get('source_identity') or '{"legacy":true}').get('legacy')
    for key, expected in (('schema_version', 2 if admitted else 1), ('pipeline', job['lane']), ('task_id', job['id'])):
        if key in candidate and candidate[key] != expected:
            raise ValueError(f'candidate {key} conflicts with queued job')
        candidate[key] = expected
    campaign_id = job.get('candidate_id')
    if campaign_id and admitted:
        if 'candidate_id' in candidate and candidate['candidate_id'] != campaign_id:
            raise ValueError('candidate candidate_id conflicts with immutable campaign identity')
        candidate['candidate_id'] = campaign_id
    if job.get('workflow_key'):
        if 'source_identity_sha256' in candidate and candidate['source_identity_sha256'] != job['workflow_key']:
            raise ValueError('candidate source identity conflicts with admission ledger')
        candidate['source_identity_sha256'] = job['workflow_key']
    candidate.setdefault('author', 'codex-cli-gpt-5.6-luna-medium')
    source = candidate.get('source')
    if isinstance(source, dict):
        repository = canonical_repository(source.get('repository', job['repository']))
        if repository != job['repository']:
            raise ValueError('candidate repository conflicts with queued source')
        source['repository'] = repository
        if admitted:
            identity = json.loads(job['source_identity'])
            if job['lane'] != 'skills' and source.get('base_commit') != identity['revision']:
                raise ValueError('candidate revision conflicts with admitted source identity')
            if job['lane'] == 'pr-issue' and normalized_text(source.get('reference', '')) != identity['reference']:
                raise ValueError('candidate issue/PR conflicts with admitted source identity')
            if job['lane'] == 'skills':
                hashes = {value.rpartition('@')[2].removeprefix('sha256:')
                          for value in source.get('skill_paths', [])}
                if identity['skill_hash'] not in hashes:
                    raise ValueError('candidate skill hash conflicts with admitted source identity')
    return validate(candidate)


class Queue:
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.execute('PRAGMA journal_mode=WAL')
            existing = db.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='jobs'").fetchone()
            if existing and 'candidate_id' not in existing['sql']:
                # One-time additive migration.  Legacy IDs, attempts and evidence
                # remain byte-for-byte addressable; only the overly broad UNIQUE
                # repository constraint is removed.
                db.execute('ALTER TABLE jobs RENAME TO jobs_legacy_campaign_v1')
            db.executescript('''
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, candidate_id TEXT NOT NULL UNIQUE,
                    task_id TEXT NOT NULL UNIQUE, lane TEXT NOT NULL,
                    repository TEXT NOT NULL, source_key TEXT, workflow_key TEXT,
                    source_identity TEXT, state TEXT NOT NULL DEFAULT 'queued',
                    attempt INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL,
                    token TEXT, lease REAL, result TEXT);
                CREATE TABLE IF NOT EXISTS attempts (
                    job TEXT, number INTEGER, token TEXT UNIQUE, started REAL, finished REAL,
                    state TEXT, result TEXT, PRIMARY KEY(job, number));
                CREATE TABLE IF NOT EXISTS reviews (
                    id TEXT PRIMARY KEY, job TEXT, result TEXT);
                CREATE TABLE IF NOT EXISTS checks (
                    id TEXT PRIMARY KEY, job TEXT, result TEXT);
                CREATE TABLE IF NOT EXISTS operator_events (
                    at REAL, job TEXT, action TEXT);
                CREATE TABLE IF NOT EXISTS admissions (
                    candidate_id TEXT PRIMARY KEY, task_id TEXT NOT NULL,
                    source_key TEXT NOT NULL, workflow_key TEXT NOT NULL,
                    identity_json TEXT NOT NULL, decision TEXT NOT NULL,
                    reason TEXT, created REAL NOT NULL);
                CREATE INDEX IF NOT EXISTS admissions_workflow ON admissions(workflow_key,decision);
                CREATE TABLE IF NOT EXISTS campaign_config (
                    config_json TEXT NOT NULL, created REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS budget_reservations (
                    token TEXT PRIMARY KEY, candidate_id TEXT NOT NULL, stage TEXT NOT NULL,
                    reserved_dollars REAL NOT NULL, actual_dollars REAL,
                    call_count INTEGER NOT NULL, state TEXT NOT NULL,
                    created REAL NOT NULL, finished REAL);
                CREATE TABLE IF NOT EXISTS stage_attempts (
                    candidate_id TEXT NOT NULL, stage TEXT NOT NULL, number INTEGER NOT NULL,
                    token TEXT PRIMARY KEY, reservation_token TEXT, started REAL NOT NULL,
                    lease REAL NOT NULL, finished REAL, state TEXT NOT NULL, result TEXT,
                    UNIQUE(candidate_id,stage,number));
                CREATE UNIQUE INDEX IF NOT EXISTS one_running_stage
                    ON stage_attempts(candidate_id,stage) WHERE state='running';
                CREATE TABLE IF NOT EXISTS promotions (
                    candidate_id TEXT PRIMARY KEY, task_id TEXT NOT NULL UNIQUE,
                    fingerprint TEXT NOT NULL UNIQUE, policy_version TEXT NOT NULL,
                    approval_json TEXT NOT NULL, created REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS storage_objects (
                    path TEXT PRIMARY KEY, candidate_id TEXT NOT NULL,
                    bytes INTEGER NOT NULL, recorded REAL NOT NULL);
            ''')
            legacy = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='jobs_legacy_campaign_v1'").fetchone()
            if legacy:
                for row in db.execute('SELECT * FROM jobs_legacy_campaign_v1').fetchall():
                    candidate_id = 'cand-' + hashlib.sha256(('legacy:' + row['id']).encode()).hexdigest()[:32]
                    source_key = hashlib.sha256(('legacy-source:' + row['repository']).encode()).hexdigest()
                    workflow_key = hashlib.sha256(('legacy-workflow:' + row['id']).encode()).hexdigest()
                    identity = {'legacy': True, 'lane': row['lane'], 'repository': row['repository'],
                                'legacy_task_id': row['id']}
                    db.execute('''INSERT OR IGNORE INTO jobs
                        (id,candidate_id,task_id,lane,repository,source_key,workflow_key,source_identity,
                         state,attempt,max_attempts,token,lease,result) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                        (row['id'], candidate_id, row['id'], row['lane'], row['repository'],
                         source_key, workflow_key, stable_json(identity), row['state'], row['attempt'],
                         row['max_attempts'], row['token'], row['lease'], row['result']))
                    db.execute('''INSERT OR IGNORE INTO admissions VALUES(?,?,?,?,?,'admitted',?,?)''',
                               (candidate_id, row['id'], source_key, workflow_key,
                                stable_json(identity), 'migrated legacy queue record', 0))
                db.execute('DROP TABLE jobs_legacy_campaign_v1')
        self.control = CampaignControl(self.path, canonical_repository)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(str(self.path), timeout=30)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def enqueue(self, lane, repository, max_attempts=2, *, identity=None,
                task_id=None, candidate_id=None):
        if lane not in LANES or not 1 <= max_attempts <= 5:
            raise ValueError('invalid lane or attempt limit')
        repository = canonical_repository(repository)
        ident = task_id or lane + '-' + hashlib.sha256(repository.encode()).hexdigest()[:12]
        if identity is not None:
            identity = dict(identity)
            identity.update(lane=lane, repository=repository)
            self.control.admit(identity, ident, max_attempts, candidate_id)
            return ident
        # Compatibility path for diagnostic fixtures and migrated callers. New
        # campaign CLI admissions always supply the full immutable identity.
        candidate_id = candidate_id or 'cand-' + uuid.uuid4().hex
        source_key = hashlib.sha256(('legacy-source:' + repository).encode()).hexdigest()
        workflow_key = hashlib.sha256(('legacy-workflow:' + ident).encode()).hexdigest()
        legacy_identity = {'legacy': True, 'lane': lane, 'repository': repository,
                           'workflow': {'outcome': ident}}
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM jobs WHERE repository=?', (repository,)).fetchone():
                raise sqlite3.IntegrityError('compatibility admissions allow one job per repository; supply identity= for campaign reuse')
            db.execute('''INSERT INTO jobs
                (id,candidate_id,task_id,lane,repository,source_key,workflow_key,source_identity,max_attempts)
                VALUES(?,?,?,?,?,?,?,?,?)''',
                (ident, candidate_id, ident, lane, repository, source_key, workflow_key,
                 stable_json(legacy_identity), max_attempts))
            db.execute('INSERT INTO admissions VALUES(?,?,?,?,?,"admitted",?,?)',
                       (candidate_id, ident, source_key, workflow_key, stable_json(legacy_identity),
                        'compatibility admission without campaign workflow receipt', time.time()))
        return ident

    def configured(self):
        with self.connect() as db:
            return db.execute('SELECT 1 FROM campaign_config').fetchone() is not None

    def claim(self, seconds=120, lane=None):
        if lane is not None and lane not in LANES:
            raise ValueError('invalid lane')
        now = time.time()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            expired = db.execute("SELECT * FROM jobs WHERE state='running' AND lease<?", (now,)).fetchall()
            for job in expired:
                db.execute("UPDATE attempts SET state='lease_expired',finished=? WHERE token=? AND finished IS NULL", (now, job['token']))
                db.execute("UPDATE jobs SET state=?,token=NULL WHERE id=?", (
                    'failed' if job['attempt'] >= job['max_attempts'] else 'queued', job['id']))
            if lane is None:
                row = db.execute("SELECT * FROM jobs WHERE state='queued' ORDER BY id LIMIT 1").fetchone()
            else:
                row = db.execute("SELECT * FROM jobs WHERE state='queued' AND lane=? ORDER BY id LIMIT 1",
                                 (lane,)).fetchone()
            if row is None:
                return None
            job = dict(row)
            job.update(token=uuid.uuid4().hex, attempt=row['attempt'] + 1)
            db.execute("UPDATE jobs SET state='running',attempt=?,token=?,lease=? WHERE id=?",
                       (job['attempt'], job['token'], now + seconds, job['id']))
            db.execute('INSERT INTO attempts(job,number,token,started,state) VALUES(?,?,?,?,?)',
                       (job['id'], job['attempt'], job['token'], now, 'running'))
            return job

    def retry(self, ident):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
            if job is None or job['state'] not in ('failed', 'needs_review') or job['attempt'] >= 5:
                raise ValueError('retry requires a completed job with fewer than five author attempts')
            db.execute("UPDATE jobs SET state='queued',max_attempts=? WHERE id=?", (job['attempt'] + 1, ident))
            db.execute('INSERT INTO operator_events VALUES(?,?,?)', (time.time(), ident, 'authorize_one_repair'))

    def heartbeat(self, job):
        with self.connect() as db:
            return db.execute("UPDATE jobs SET lease=? WHERE id=? AND token=? AND state='running' AND lease>=?",
                              (time.time() + 120, job['id'], job['token'], time.time())).rowcount == 1

    def release_unstarted(self, job):
        """Undo a claim when admission control refused before any call launched."""
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            changed = db.execute("UPDATE jobs SET state='queued',attempt=attempt-1,token=NULL,lease=NULL WHERE id=? AND token=? AND state='running'",
                                 (job['id'], job['token'])).rowcount
            if changed != 1:
                raise RuntimeError('cannot release a stale claim')
            db.execute('DELETE FROM attempts WHERE token=? AND state="running"', (job['token'],))

    def finish(self, job, state, result):
        if state not in ('needs_review', 'failed', 'queued'):
            raise ValueError('workers cannot accept tasks')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            changed = db.execute("UPDATE jobs SET state=?,result=?,token=NULL WHERE id=? AND token=? AND state='running' AND lease>=?",
                                 (state, json.dumps(result), job['id'], job['token'], time.time())).rowcount
            if changed != 1:
                raise RuntimeError('lease lost; refusing stale result')
            db.execute('UPDATE attempts SET state=?,result=?,finished=? WHERE token=?',
                       (state, json.dumps(result), time.time(), job['token']))

    def report(self):
        with self.connect() as db:
            jobs = [dict(r) for r in db.execute('SELECT * FROM jobs ORDER BY id')]
            attempts = [dict(r) for r in db.execute('SELECT * FROM attempts ORDER BY started')]
            reviews = [dict(r) for r in db.execute('SELECT * FROM reviews ORDER BY rowid')]
            checks = [dict(r) for r in db.execute('SELECT * FROM checks ORDER BY rowid')]
            events = [dict(r) for r in db.execute('SELECT * FROM operator_events ORDER BY at')]
            admissions = [dict(r) for r in db.execute('SELECT * FROM admissions ORDER BY created')]
            stages = [dict(r) for r in db.execute('SELECT * FROM stage_attempts ORDER BY started')]
            reservations = [dict(r) for r in db.execute('SELECT * FROM budget_reservations ORDER BY created')]
            promotions = [dict(r) for r in db.execute('SELECT * FROM promotions ORDER BY created')]
        counts = {lane: {} for lane in LANES}
        usage = {}
        for job in jobs:
            lane = counts[job['lane']]
            lane[job['state']] = lane.get(job['state'], 0) + 1
        for attempt in attempts + reviews + checks:
            for key, value in json.loads(attempt['result'] or '{}').get('usage', {}).items():
                usage[key] = usage.get(key, 0) + value
        stage_summary = {}
        for row in stages:
            summary = stage_summary.setdefault(row['stage'], {'states': {}, 'elapsed_seconds': 0})
            summary['states'][row['state']] = summary['states'].get(row['state'], 0) + 1
            if row['finished'] is not None:
                summary['elapsed_seconds'] += max(0, row['finished'] - row['started'])
        budget_summary = {}
        for row in reservations:
            summary = budget_summary.setdefault(row['stage'], {'reserved_dollars': 0,
                'accounted_dollars': 0, 'calls': 0, 'uncertain': 0})
            summary['reserved_dollars'] += row['reserved_dollars']
            summary['accounted_dollars'] += (row['actual_dollars'] if row['actual_dollars'] is not None
                                               else row['reserved_dollars'])
            summary['calls'] += row['call_count']
            summary['uncertain'] += row['state'] == 'uncertain'
        admitted_by_lane = {lane: sum(a['decision'] == 'admitted' and
                                      json.loads(a['identity_json']).get('lane') == lane
                                      for a in admissions) for lane in LANES}
        promoted_ids = {p['candidate_id'] for p in promotions}
        accepted_by_lane = {lane: sum(j['candidate_id'] in promoted_ids and j['lane'] == lane
                                      for j in jobs) for lane in LANES}
        return {'model': MODEL, 'reasoning_effort': EFFORT, 'counts': counts,
                'usage': usage, 'jobs': jobs, 'attempts': attempts, 'reviews': reviews, 'checks': checks,
                'operator_events': events, 'admissions': admissions, 'stage_attempts': stages,
                'budget_reservations': reservations, 'promotions': promotions,
                'stage_summary': stage_summary, 'budget_summary': budget_summary,
                'yield': {lane: {'admitted': admitted_by_lane[lane],
                                 'accepted': accepted_by_lane[lane],
                                 'eventual_acceptance': (accepted_by_lane[lane] / admitted_by_lane[lane]
                                    if admitted_by_lane[lane] else None)} for lane in LANES},
                'usage_caveat': 'Completed CLI turns only; interrupted calls may be unmetered. No dollar estimate without configured rates.'}


def run_process(command, cwd, stdout, stderr, timeout, lost, stdin=None):
    """Kill the whole local process group on timeout or lost lease."""
    environment = os.environ.copy()
    storage_scope = None
    if command and command[0] == 'codex' and environment.get('GENERAL_ISOLATED_WORKER') == '1':
        socket_path = Path(environment.get('GENERAL_EGRESS_SOCKET', '')).resolve()
        codex_home = Path(environment.get('CODEX_HOME', '')).resolve()
        codex_binary = Path(shutil.which('codex') or '').resolve()
        if not socket_path.is_socket() or not (codex_home / 'auth.json').is_file() or not codex_binary.is_file():
            raise ValueError('isolated worker requires egress socket, private CODEX_HOME, and codex binary')
        scope = Path(cwd).resolve().parent if Path(cwd).name == 'workspace' else Path(cwd).resolve()
        storage_scope = scope
        (scope / '.tmp').mkdir(exist_ok=True)
        node_root = next((parent for parent in codex_binary.parents
                          if (parent / 'bin/node').is_file()), None)
        if node_root is None:
            raise ValueError('cannot locate isolated Codex Node runtime')
        proxy = 'http://0.0.0.0:18080'
        command = ['bwrap', '--die-with-parent', '--new-session', '--unshare-all',
                   '--ro-bind', '/usr', '/usr', '--symlink', 'usr/bin', '/bin',
                   '--symlink', 'usr/sbin', '/sbin', '--symlink', 'usr/lib', '/lib',
                   '--symlink', 'usr/lib64', '/lib64', '--ro-bind', '/etc', '/etc',
                   '--proc', '/proc', '--dev', '/dev', '--bind', str(scope / '.tmp'), '/tmp',
                   '--dir', '/run', '--ro-bind', str(socket_path), '/run/general-egress.sock',
                   '--bind', str(scope), str(scope), '--bind', str(codex_home), str(codex_home),
                   '--ro-bind', str(node_root), str(node_root), '--chdir', str(cwd), '--clearenv',
                   '--setenv', 'PATH', str(node_root / 'bin') + ':/usr/local/bin:/usr/bin:/bin',
                   '--setenv', 'HOME', str(scope / '.home'), '--setenv', 'CODEX_HOME', str(codex_home),
                   '--setenv', 'HTTP_PROXY', proxy, '--setenv', 'HTTPS_PROXY', proxy,
                   '--setenv', 'http_proxy', proxy, '--setenv', 'https_proxy', proxy,
                   '--', '/bin/bash', '-c',
                   'socat TCP-LISTEN:18080,bind=0.0.0.0,reuseaddr,fork UNIX-CONNECT:/run/general-egress.sock & sleep 0.1; exec "$@"',
                   'isolated-codex', *command]
        (scope / '.home').mkdir(exist_ok=True)
    owner = None
    if str(ROOT / 'tools/qa_task.py') in command:
        owner = uuid.uuid4().hex
        environment['GENERAL_QA_RUN_ID'] = owner
    with stdout.open('w') as out, stderr.open('w') as err:
        process = subprocess.Popen(command, cwd=str(cwd), stdin=stdin,
                                   stdout=out, stderr=err, start_new_session=True, env=environment)
        deadline = time.monotonic() + timeout
        next_storage_check = time.monotonic()
        storage_limit = int(environment.get('GENERAL_WORKER_STORAGE_BYTES', str(4 * 1024**3)))
        try:
            while process.poll() is None:
                if lost.wait(0.25) or time.monotonic() >= deadline:
                    raise TimeoutError('stage deadline exceeded or lease lost')
                if storage_scope is not None and time.monotonic() >= next_storage_check:
                    used = directory_file_bytes(storage_scope)
                    if used > storage_limit:
                        raise TimeoutError('disposable worker storage limit exceeded')
                    next_storage_check = time.monotonic() + 2
            return process.returncode
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            if owner:
                # Docker containers can outlive their client process group.
                for kind, listing in (('container', ['docker', 'ps', '-aq']),
                                      ('image', ['docker', 'image', 'ls', '-q'])):
                    try:
                        ids = subprocess.check_output(listing + ['--filter', 'label=general.factory=' + owner],
                                                      text=True, timeout=15).split()
                        ids = [item for item in ids if re.fullmatch(r'(sha256:)?[0-9a-f]{12,64}', item)]
                        if ids:
                            subprocess.run(['docker', kind, 'rm', '--force', *ids],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                    except (OSError, subprocess.SubprocessError):
                        # Retain the scoped owner label so an operator can recover leftovers.
                        with stderr.open('a') as err:
                            err.write(f'Cleanup incomplete: Docker label general.factory={owner}\n')
            if storage_scope is not None:
                # These are per-call scratch roots mounted inside the disposable
                # worker. Never retain repository clones or transient caches in
                # the evidence bundle.
                shutil.rmtree(storage_scope / '.tmp', ignore_errors=True)
                shutil.rmtree(storage_scope / '.home', ignore_errors=True)


def usage_from_events(path):
    usage, thread = {}, None
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get('type') == 'thread.started':
                thread = event.get('thread_id')
            if event.get('type') == 'turn.completed':
                for key, value in event.get('usage', {}).items():
                    if isinstance(value, int):
                        usage[key] = usage.get(key, 0) + value
    return usage, thread


def luna_usage_cost(usage):
    """Conservatively price a completed gpt-5.6-luna turn from CLI usage."""
    input_tokens = max(0, int(usage.get('input_tokens', 0)))
    cached_tokens = min(input_tokens, max(0, int(usage.get('cached_input_tokens', 0))))
    output_tokens = max(0, int(usage.get('output_tokens', 0)))
    long_context = input_tokens > 272_000
    input_rate = 0.40 if long_context else 0.20
    cached_rate = 0.04 if long_context else 0.02
    output_rate = 1.80 if long_context else 1.20
    return ((input_tokens - cached_tokens) * input_rate + cached_tokens * cached_rate
            + output_tokens * output_rate) / 1_000_000


def session_context(thread):
    if not thread or not re.fullmatch(r'[0-9a-f-]{36}', thread):
        raise ValueError('missing valid author/reviewer session id')
    session_root = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'sessions'
    matches = list(session_root.glob('*/*/*/rollout-*-' + thread + '.jsonl'))
    contexts = []
    for path in matches:
        with path.open() as stream:
            for line in stream:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get('type') == 'turn_context':
                    payload = event['payload']
                    contexts.append({'model': payload.get('model'), 'effort': payload.get('effort')})
    if not contexts or any(c != {'model': MODEL, 'effort': EFFORT} for c in contexts):
        raise ValueError('recorded CLI model/reasoning settings missing or incorrect')
    return {'thread_id': thread, 'contexts': contexts}


def seal(root):
    records = {}
    for path in sorted(root.rglob('*')):
        parts = path.relative_to(root).parts
        # Virtualenvs/checkouts are disposable scratch, not the reviewed package.
        if len(parts) > 1 and parts[0] == 'workspace' and parts[1] not in {
                'tasks', 'skills', 'receipts', 'contract', 'candidate.json',
                'prompt.txt', 'feedback.txt', 'final.txt', 'instruction.md', 'qa'}:
            continue
        if path.is_symlink():
            raise ValueError('symlinks forbidden in evidence bundle')
        if path.is_file() and path != root / 'seal.json':
            records[path.relative_to(root).as_posix()] = {
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'mode': path.stat().st_mode & 0o777}
    return records


def export_batch(queue, destination):
    """Portable evidence snapshot, excluding author scratch and running attempts."""
    report = queue.report()
    if any(job['state'] == 'running' for job in report['jobs']):
        raise ValueError('stop workers before exporting evidence')
    destination.mkdir(parents=True, exist_ok=False)
    index = {}
    for record in report['attempts'] + report['reviews'] + report['checks']:
        result = json.loads(record['result'] or '{}')
        if not result.get('seal_sha256'):
            continue
        source = Path(result['bundle'])
        if verify_seal(source) != result['seal_sha256']:
            raise ValueError('ledger/bundle mismatch during export')
        relative = source.resolve().relative_to(queue.path.parent)
        target = destination / relative
        target.mkdir(parents=True)
        for name in json.loads((source / 'seal.json').read_text()):
            output = target / name
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / name, output)
        shutil.copy2(source / 'seal.json', target / 'seal.json')
        index[relative.as_posix()] = result['seal_sha256']
    shutil.copytree(queue.path.parent / 'sources', destination / 'sources')
    (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (destination / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    contexts = {}
    for record in report['attempts'] + report['reviews'] + report['checks']:
        thread = json.loads(record['result'] or '{}').get('thread_id')
        if thread and thread not in contexts:
            try:
                contexts[thread] = session_context(thread)
            except (OSError, ValueError) as exc:
                contexts[thread] = {'verification_error': str(exc)}
    (destination / 'session-contexts.json').write_text(json.dumps(contexts, indent=2) + '\n')
    (destination / 'seal.json').write_text(json.dumps(seal(destination), indent=2) + '\n')
    verify_export(destination)


def verify_export(destination):
    verify_seal(destination)
    index = json.loads((destination / 'index.json').read_text())
    for relative, digest in index.items():
        bundle = destination / relative
        if not bundle.resolve().is_relative_to(destination.resolve()):
            raise ValueError('invalid export path')
        if verify_seal(bundle) != digest:
            raise ValueError('export evidence changed')
    return len(index)


def verify_seal(root):
    expected = json.loads((root / 'seal.json').read_text())
    if expected != seal(root):
        raise ValueError('evidence bundle changed')
    return hashlib.sha256((root / 'seal.json').read_bytes()).hexdigest()


def verify_record(queue, bundle):
    digest = verify_seal(bundle)
    with queue.connect() as db:
        records = db.execute('SELECT result FROM attempts WHERE result IS NOT NULL UNION ALL SELECT result FROM checks').fetchall()
    if not any(json.loads(r['result']).get('bundle') == str(bundle)
               and json.loads(r['result']).get('seal_sha256') == digest for r in records):
        raise ValueError('bundle seal does not match trusted queue ledger')
    return digest


def check_skill_sources(work, candidate):
    if candidate['pipeline'] != 'skills':
        return
    for reference in candidate['source']['skill_paths']:
        relative, separator, expected = reference.rpartition('@')
        expected = expected.removeprefix('sha256:')
        if not separator or not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('skill references require a SHA256 content hash')
        path = work / relative
        if not path.resolve().is_relative_to((work / 'skills').resolve()) or path.is_symlink():
            raise ValueError('skill must be inside workspace/skills')
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('skill hash mismatch')
        content = path.read_text()
        if not content.startswith('---\n') or '\nname:' not in content or '\ndescription:' not in content:
            raise ValueError('skill requires name and description frontmatter')


def recheck(queue, ident, runtime=True):
    """Rerun trusted QA on unchanged generated content, without paying to reauthor."""
    with queue.connect() as db:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
    if job is None or job['state'] not in ('queued', 'failed', 'needs_review'):
        raise ValueError('recheck requires a completed draft')
    original = json.loads(job['result'])
    source = Path(original['bundle'])
    candidate = validate(json.loads((source / 'workspace/candidate.json').read_text()))
    if fingerprint(source / 'workspace/tasks' / ident, candidate) != original.get('fingerprint'):
        raise ValueError('authored package changed; needs a new authoring attempt')
    if not original.get('thread_id'):
        raise ValueError('missing recorded author session')
    check_id = uuid.uuid4().hex
    output = queue.path.parent / 'checks' / ident / check_id
    work = output / 'workspace'
    work.mkdir(parents=True)
    for name in ('tasks', 'skills', 'receipts'):
        shutil.copytree(source / 'workspace' / name, work / name, symlinks=True)
    shutil.copy2(source / 'workspace/candidate.json', work / 'candidate.json')
    if (source / 'events.jsonl').exists():
        shutil.copy2(source / 'events.jsonl', output / 'author-events.jsonl')
    result = {'bundle': str(output), 'origin_bundle': str(source), 'fingerprint': original['fingerprint'],
              'thread_id': original['thread_id'],
              'kind': 'qa_recheck' if runtime else 'static_qa_resume', 'usage': {},
              'model': original['model'], 'reasoning_effort': original['reasoning_effort']}
    stage_claim = queue.control.claim_stage(
        job['candidate_id'], 'repeat_runtime' if runtime else 'build', 3720)
    try:
        check_skill_sources(work, candidate)
        if not any(p.is_file() for p in (work / 'receipts').rglob('*')):
            raise ValueError('source receipts are missing')
        duplicates = near_duplicates(work / 'tasks' / ident, (ROOT / 'tasks').iterdir())
        (output / 'duplicates.json').write_text(json.dumps(duplicates, indent=2) + '\n')
        if duplicates:
            raise ValueError('near-duplicate instruction detected')
        command = [sys.executable, str(ROOT / 'tools/qa_task.py'), '--candidate', str(work / 'candidate.json'),
                   '--suite-root', str(work), '--output-root', str(output / 'qa'), '--runtime-backend', 'docker',
                   '--runtime-only' if runtime else '--static-only']
        code = run_process(command, work, output / 'qa.log', output / 'qa.stderr', 3600, threading.Event())
        if code:
            raise ValueError('shared QA failed; inspect qa logs')
        if fingerprint(work / 'tasks' / ident, candidate) != original['fingerprint']:
            raise ValueError('package changed during QA')
        result['status'] = 'needs_review'
    except (OSError, ValueError, TimeoutError) as exc:
        result.update(status='failed', error=str(exc))
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    result['seal_sha256'] = verify_seal(output)
    queue.control.account_storage(output, job['candidate_id'])
    with queue.connect() as db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('INSERT INTO checks VALUES(?,?,?)', (check_id, ident, json.dumps(result)))
        changed = db.execute('UPDATE jobs SET state=?,result=? WHERE id=? AND result=?',
                   (result['status'], json.dumps(result), ident, job['result'])).rowcount
        if changed != 1:
            raise RuntimeError('job changed during recheck')
    queue.control.finish_stage(stage_claim, 'failed' if result.get('error') else 'passed', result)
    print(json.dumps(result, indent=2))
    return 1 if result.get('error') else 0


def instruction_shingles(text):
    words = re.findall(r'[a-z0-9]+', text.lower())
    return {tuple(words[i:i + 5]) for i in range(len(words) - 4)}


def near_duplicates(task, other_tasks, threshold=0.65):
    signature = instruction_shingles((task / 'instruction.md').read_text())
    matches = []
    for other in other_tasks:
        if other.resolve() == task.resolve() or not (other / 'instruction.md').is_file():
            continue
        reference = instruction_shingles((other / 'instruction.md').read_text())
        union = signature | reference
        score = len(signature & reference) / len(union) if union else 1.0
        if score >= threshold:
            matches.append({'task': other.name, 'similarity': score})
    return matches


def independent_review(queue, ident, timeout, reserve_dollars=None):
    with queue.connect() as db:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
    if job is None or job['state'] != 'needs_review':
        raise ValueError('review requires a draft that passed requested QA controls')
    author = json.loads(job['result'])
    bundle = Path(author['bundle'])
    verify_record(queue, bundle)
    reservation = None
    if queue.configured():
        if reserve_dollars is None:
            raise ValueError('review requires an approved dollar reservation')
        reservation = queue.control.reserve('review', job['candidate_id'], reserve_dollars)
    stage_claim = queue.control.claim_stage(job['candidate_id'], 'review',
                                            max(120, timeout + 60), reservation)
    review_id = uuid.uuid4().hex
    output = queue.path.parent / 'reviews' / ident / review_id
    work = output / 'workspace'
    work.mkdir(parents=True)
    for name in ('tasks', 'skills', 'receipts'):
        shutil.copytree(bundle / 'workspace' / name, work / name)
    shutil.copy2(bundle / 'workspace/candidate.json', work / 'candidate.json')
    if (bundle / 'qa').is_dir():
        shutil.copytree(bundle / 'qa', work / 'qa')
    schema = {'type': 'object', 'additionalProperties': False,
              'required': ['verdict', 'criteria', 'findings'], 'properties': {
                  'verdict': {'type': 'string', 'enum': ['pass', 'revise', 'reject']},
                  'criteria': {'type': 'array', 'items': {'type': 'object', 'additionalProperties': False,
                      'required': ['criterion', 'test', 'gap'], 'properties': {
                          key: {'type': 'string'} for key in ('criterion', 'test', 'gap')}}},
                  'findings': {'type': 'array', 'items': {'type': 'string'}}}}
    (output / 'schema.json').write_text(json.dumps(schema))
    prompt = '''Independently review this original evaluation task. Read candidate.json, task instruction,
environment, solution and verifier, source receipts and any skills. Do not modify files.
Map EVERY candidate acceptance criterion (copy its exact wording) to specific test files/functions; identify missing behavioral coverage,
answer leaks, unverifiable provenance, baseline/oracle failures, brittle checks, exploitable graders,
unrealistic instructions and weak difficulty. Inspect code, not author claims. Report concrete actionable findings.
An absent or incomplete receipt is a gap, not presumed valid. Do not claim runtime, contamination or blind-pilot
clearance from static reading. This is independent design review only. Return the required JSON object.
When available, qa/ contains independently recorded runtime evidence; distinguish it from author assertions.
The solution and hidden tests are supplied to YOU for review, not to the solving agent. Inspect the actual Dockerfile
before alleging answer leaks. Binary reward 0 with verifier exit code 0 is valid for this harness; do not call that
alone a vulnerability. Task-level timeouts are declared in task.toml. Separate confirmed defects from hypotheses,
trace helper functions before alleging bugs, and do not demand behaviors absent from the stated contract.
'''
    (output / 'prompt.txt').write_text(prompt)
    result = {'job': ident, 'author_fingerprint': author['fingerprint'], 'bundle': str(output),
              'author_seal': author['seal_sha256'], 'model': MODEL, 'reasoning_effort': EFFORT}
    try:
        with (output / 'prompt.txt').open() as source:
            code = run_process(['codex', '-a', 'never', 'exec', '--ignore-user-config', '-m', MODEL,
                '-c', 'model_reasoning_effort="medium"', '-s', 'read-only', '--skip-git-repo-check',
                '-C', str(work), '--json', '--output-schema', str(output / 'schema.json'),
                '-o', str(output / 'review.json'), '-'], work, output / 'events.jsonl',
                output / 'stderr.log', timeout, threading.Event(), source)
        if code:
            raise ValueError(f'reviewer CLI exited {code}')
        review = json.loads((output / 'review.json').read_text())
        candidate = json.loads((work / 'candidate.json').read_text())
        if review.get('verdict') not in ('pass', 'revise', 'reject') or not isinstance(review.get('findings'), list):
            raise ValueError('invalid reviewer output')
        if {c['criterion'] for c in review['criteria']} != set(candidate['acceptance']):
            raise ValueError('review did not map every exact acceptance criterion')
        result['review'] = review
        if fingerprint(work / 'tasks' / ident, candidate) != author['fingerprint']:
            raise ValueError('review input changed')
        verify_record(queue, bundle)
    except (OSError, ValueError, KeyError, TypeError, TimeoutError) as exc:
        result['error'] = str(exc)
    result['usage'], result['thread_id'] = usage_from_events(output / 'events.jsonl')
    if not result['thread_id'] or result['thread_id'] == author.get('thread_id'):
        result['error'] = 'review requires an independent recorded session'
    try:
        result['session_context'] = session_context(result['thread_id'])
    except ValueError as exc:
        result['error'] = str(exc)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (output / 'seal.json').write_text(json.dumps(seal(output), indent=2) + '\n')
    result['seal_sha256'] = verify_seal(output)
    queue.control.account_storage(output, job['candidate_id'])
    with queue.connect() as db:
        db.execute('INSERT INTO reviews VALUES(?,?,?)', (review_id, ident, json.dumps(result)))
    review_state = ('failed' if result.get('error') else
                    ('passed' if result.get('review', {}).get('verdict') == 'pass' else 'held'))
    queue.control.finish_stage(stage_claim, review_state, result)
    if reservation:
        if result['usage']:
            queue.control.reconcile(reservation, luna_usage_cost(result['usage']))
        else:
            queue.control.mark_charge_uncertain(
                reservation, 'completed review has no parseable usage event')
    print(json.dumps(result, indent=2))
    return 1 if result.get('error') else 0


def prepare(work, job):
    docs = work / 'contract'
    docs.mkdir(parents=True)
    for name in ('README.md', job['lane'] + '.md'):
        shutil.copy2(ROOT / 'authoring' / name, docs / name)
    # Authoring schema only. No tasks, solutions, QA references or coverage specs.
    shutil.copy2(ROOT / 'tools/author_task.py', docs / 'author_task.py')
    for name in ('lint_tasks.py', 'check_binary_reward.py', '_toml_compat.py'):
        shutil.copy2(ROOT / 'tools' / name, docs / name)
    for name in ('tasks', 'skills', 'receipts'):
        (work / name).mkdir()
    admitted = not json.loads(job.get('source_identity') or '{"legacy":true}').get('legacy')
    if admitted:
        (docs / 'admission.json').write_text(json.dumps(json.loads(job['source_identity']), indent=2) + '\n')
        identity = json.loads(job['source_identity'])
        if job['lane'] == 'skills':
            skill_source = Path(identity['skill_artifact']).resolve()
            if hashlib.sha256(skill_source.read_bytes()).hexdigest() != identity['skill_hash']:
                raise ValueError('admitted skill artifact changed')
            skill_target = work / 'skills' / skill_source.parent.name
            skill_target.mkdir()
            shutil.copy2(skill_source, skill_target / 'SKILL.md')
    schema_version = 2 if admitted else 1
    prompt = f'''Create ONE original general evaluation task via the {job['lane']} lane.
Source repository: {job['repository']}. Task id: {job['id']}.
Immutable campaign candidate id: {job.get('candidate_id', 'legacy')}. Approved source/workflow identity SHA256: {job.get('workflow_key', 'legacy')}.
Read contract/README.md, contract/{job['lane']}.md, and (when present) contract/admission.json.
Implement the approved workflow exactly; do not silently select another objective. Use no benchmarks or existing evaluation tasks as sources.
Inspect upstream code/documentation and record actual immutable commits, license and baseline commands/results in receipts/.
For pr-issue choose a real bounded upstream issue/PR; verify base and reproduction, keep fix/history out of task image.
For skills use the pre-approved immutable skill already supplied in skills/<name>/SKILL.md; do not modify it.
Apply it to a materially new scenario and record its path and SHA256.
Write candidate.json satisfying contract/author_task.py validate(), with pipeline={job['lane']}, schema_version={schema_version},
author=codex-cli-gpt-5.6-luna-medium. Use the exact task id above and source.repository above.
Also copy the exact campaign candidate id to candidate_id and the approved identity hash to source_identity_sha256.
For schema 2 include criterion_tests mapping every exact acceptance string to concrete test files/functions,
captured baseline commands/results, dependency_pins, and explicit cpus/memory/agent/verifier resource_limits.
Write tasks/{job['id']}/ with task.toml schema_version="1.4", instruction.md,
environment/Dockerfile FROM bench-base:python-3.12 (or bench-base:ubuntu-24.04), WORKDIR /app,
solution/solve.sh and tests/test.sh executable. Tests produce only binary /logs/verifier/reward.txt, guarded against failures.
Reward MUST be 1 for correct work (oracle) and 0 for failing or absent work (untouched baseline); it is NOT an exit code.
Metadata requires difficulty easy/medium/hard, category one of {','.join(sorted(CATEGORIES))}; verifier_kind="executes-deliverable",
deliverables list of /app paths explicitly mentioned by instruction, oracle and verifier.
Environment requires network_mode="no-network", cpus=1, memory_mb=4096; pin dependencies and source.
Declare [verifier] timeout_sec=300 and [agent] timeout_sec=900 explicitly in task.toml.
Include difficulty.json with integer expected_expert_time_min and rubric object containing exactly
{','.join(sorted(RUBRIC_KEYS))}, each an integer 0..3.
Implement hidden behavioral cases under tests/hidden, actually invoked by verifier. Test every acceptance criterion,
regressions and plausible incomplete solutions. No answer leaks into environment. Oracle must solve; untouched baseline must fail.
Add tests/mutations/manifest.json and at least three executable, behaviorally distinct mutation scripts.
Each script must apply one plausible incomplete/incorrect approach to the pristine task. The manifest records
name, distinct kind, script, and an intended_reason regex that appears in verifier diagnostics when it fails.
The harness mounts grader files at /tests, NEVER /app/tests. Invoke /tests/hidden/... and retain diagnostic output.
Do not run Docker or access files outside this workspace except public upstream source/tools. Write no live suite files.
Keep dependencies and download sizes modest. Prefer a substantive bounded workflow over a toy formatting exercise.
Choose difficulty honestly: a straightforward localized repair may be easy. Do not default to medium.
Do not promise broad regression compatibility unless the verifier actually checks it. Map each acceptance
criterion to concrete tests in receipts, and record any coverage gaps instead of claiming unrun checks passed.
Before finishing run python3 contract/lint_tasks.py --root . --task {job['id']} and
python3 contract/check_binary_reward.py --root . --task {job['id']}; repair any failures.
These local checks are advisory copies; host QA will independently run trusted versions.
If the source cannot support a valid task, explain failure; never fabricate a PR or source receipt.
'''
    (work / 'prompt.txt').write_text(prompt)


def execute_job(queue, job, timeout, runtime):
    bundle = queue.path.parent / 'runs' / job['id'] / job['token']
    work = bundle / 'workspace'
    work.mkdir(parents=True)
    lost, stop = threading.Event(), threading.Event()

    def renew():
        while not stop.wait(20):
            try:
                if not queue.heartbeat(job):
                    lost.set()
                    return
            except sqlite3.Error:
                lost.set()
                return

    heartbeat = threading.Thread(target=renew, daemon=True)
    heartbeat.start()
    result = {'bundle': str(bundle), 'model': MODEL, 'reasoning_effort': EFFORT}
    state = 'failed'
    try:
        prepare(work, job)
        if job.get('result'):
            previous = json.loads(job['result'])
            previous_bundle = Path(previous['bundle'])
            verify_record(queue, previous_bundle)
            for name in ('tasks', 'skills', 'receipts'):
                shutil.copytree(previous_bundle / 'workspace' / name, work / name, dirs_exist_ok=True)
            if (previous_bundle / 'workspace/candidate.json').is_file():
                shutil.copy2(previous_bundle / 'workspace/candidate.json', work / 'candidate.json')
            feedback = [previous.get('error', 'Previous draft was incomplete.')]
            for path in sorted((previous_bundle / 'qa').rglob('*.log')):
                feedback.append(path.name + '\n' + path.read_text(errors='replace')[-6000:])
            for path in sorted((previous_bundle / 'qa').rglob('*result.json')):
                feedback.append(path.name + '\n' + path.read_text()[-6000:])
            with queue.connect() as db:
                reviews = db.execute('SELECT result FROM reviews WHERE job=? ORDER BY rowid DESC LIMIT 1', (job['id'],)).fetchall()
            if reviews:
                feedback.append('Independent design review:\n' + json.dumps(json.loads(reviews[0]['result']).get('review', {})))
            (work / 'feedback.txt').write_text('\n'.join(feedback)[-30000:])
            with (work / 'prompt.txt').open('a') as prompt:
                prompt.write('\nThis is a bounded repair attempt. Existing draft files and feedback.txt are provided. Fix the recorded failures and revalidate.\n')
        command = ['codex', '-a', 'never', 'exec', '--ignore-user-config', '-m', MODEL,
                   '-c', 'model_reasoning_effort="medium"', '-s', 'workspace-write',
                   '-c', 'sandbox_workspace_write.network_access=true', '--skip-git-repo-check',
                   '-C', str(work), '--json', '-o', str(work / 'final.txt'), '-']
        result['command'] = command
        with (work / 'prompt.txt').open() as prompt:
            code = run_process(command, work, bundle / 'events.jsonl', bundle / 'stderr.log', timeout, lost, prompt)
        if code:
            raise ValueError(f'author CLI exited {code}')
        _, thread_id = usage_from_events(bundle / 'events.jsonl')
        result['session_context'] = session_context(thread_id)
        shutil.copy2(work / 'candidate.json', bundle / 'raw-candidate.json')
        candidate = normalize_candidate(json.loads((work / 'candidate.json').read_text()), job)
        (work / 'candidate.json').write_text(json.dumps(candidate, indent=2) + '\n')
        if (candidate['task_id'] != job['id'] or candidate['pipeline'] != job['lane']
                or canonical_repository(candidate['source'].get('repository', '')) != job['repository']):
            raise ValueError('candidate does not match queued source/lane/id')
        result['fingerprint'] = fingerprint(work / 'tasks' / job['id'], candidate)
        check_skill_sources(work, candidate)
        if not any(p.is_file() for p in (work / 'receipts').rglob('*')):
            raise ValueError('source receipts are missing')
        comparisons = list((ROOT / 'tasks').iterdir())
        # Completed snapshots only; running workspaces may still be changing.
        with queue.connect() as db:
            previous = db.execute("SELECT result FROM jobs WHERE state='needs_review'").fetchall()
        for row in previous:
            other_root = Path(json.loads(row['result'])['bundle']) / 'workspace/tasks'
            comparisons.extend(other_root.iterdir())
        duplicates = near_duplicates(work / 'tasks' / job['id'], comparisons)
        (bundle / 'duplicates.json').write_text(json.dumps(duplicates, indent=2) + '\n')
        if duplicates:
            raise ValueError('near-duplicate instruction detected; needs diversity review')
        qa = [sys.executable, str(ROOT / 'tools/qa_task.py'), '--candidate', str(work / 'candidate.json'),
              '--suite-root', str(work), '--output-root', str(bundle / 'qa'),
              '--runtime-backend', 'docker', '--runtime-only' if runtime else '--static-only']
        build_stage = queue.control.claim_stage(job['candidate_id'], 'build', 3720)
        try:
            code = run_process(qa, work, bundle / 'qa.log', bundle / 'qa.stderr', 3600, lost)
        except BaseException as exc:
            queue.control.finish_stage(build_stage, 'failed',
                                       {'fingerprint': result['fingerprint'],
                                        'error': f'{type(exc).__name__}: {exc}', 'runtime': runtime})
            raise
        else:
            queue.control.finish_stage(build_stage, 'passed' if code == 0 else 'failed',
                                       {'fingerprint': result['fingerprint'], 'returncode': code,
                                        'runtime': runtime})
        if code:
            raise ValueError('shared QA failed; inspect qa logs')
        state = 'needs_review'
        result['remaining_gates'] = ['independent review', 'negative mutations', 'repeatability',
                                     'blind pilots', 'contamination', 'diversity', 'release approval']
        if not runtime:
            result['remaining_gates'].insert(0, 'runtime controls')
    except (OSError, ValueError, RuntimeError, TimeoutError) as exc:
        result['error'] = str(exc)
        state = 'queued' if job['attempt'] < job['max_attempts'] else 'failed'
    finally:
        result['usage'], result['thread_id'] = usage_from_events(bundle / 'events.jsonl')
        (bundle / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        try:
            (bundle / 'seal.json').write_text(json.dumps(seal(bundle), indent=2) + '\n')
            result['seal_sha256'] = verify_seal(bundle)
            queue.control.account_storage(bundle, job['candidate_id'])
        except ValueError as exc:
            state = 'failed'
            result['error'] = str(exc)
        try:
            queue.finish(job, state, result)
        finally:
            stop.set()
            heartbeat.join()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    commands = parser.add_subparsers(dest='command', required=True)
    add = commands.add_parser('enqueue')
    add.add_argument('--csv', type=Path, required=True)
    add.add_argument('--repository', required=True)
    add.add_argument('--lane', choices=LANES, required=True)
    add.add_argument('--max-attempts', type=int, default=2)
    add.add_argument('--identity', type=Path, required=True,
                     help='approved immutable source/workflow identity JSON')
    add.add_argument('--task-id', required=True, help='opaque final task id reserved at admission')
    configure = commands.add_parser('configure')
    configure.add_argument('--dollar-cap', type=float, required=True)
    configure.add_argument('--author-calls', type=int, required=True)
    configure.add_argument('--reviewer-calls', type=int, required=True)
    configure.add_argument('--pilot-calls', type=int, required=True)
    configure.add_argument('--fleet-concurrency', type=int, required=True)
    configure.add_argument('--storage-bytes', type=int, required=True)
    configure.add_argument('--approved-by', required=True)
    configure.add_argument('--policy-version', required=True)
    configure.add_argument('--isolation-receipt', type=Path, required=True)
    worker = commands.add_parser('work')
    worker.add_argument('--workers', type=int, choices=range(1, 5), default=1)
    worker.add_argument('--max-jobs', type=int, default=3, help='hard limit on author CLI invocations in this run')
    worker.add_argument('--timeout', type=int, default=1200)
    worker.add_argument('--runtime', action='store_true')
    worker.add_argument('--lane', choices=LANES,
                        help='restrict this invocation to one lane for targeted recovery')
    worker.add_argument('--reserve-dollars', type=float, required=True,
                        help='approved worst-case reservation per author invocation')
    commands.add_parser('report')
    review = commands.add_parser('review')
    review.add_argument('--job', required=True)
    review.add_argument('--timeout', type=int, default=600)
    review.add_argument('--reserve-dollars', type=float)
    check = commands.add_parser('recheck')
    check.add_argument('--job', required=True)
    check.add_argument('--static-only', action='store_true',
                       help='resume static QA on unchanged authored bytes after infrastructure failure')
    retry = commands.add_parser('retry')
    retry.add_argument('--job', required=True)
    pilot_parser = commands.add_parser('pilot')
    pilot_parser.add_argument('--job', required=True)
    pilot_parser.add_argument('--timeout', type=int, default=600)
    pilot_parser.add_argument('--reserve-dollars', type=float)
    audit_parser = commands.add_parser('audit')
    audit_parser.add_argument('--reference-root', type=Path, required=True)
    qualify_parser = commands.add_parser('qualify')
    qualify_parser.add_argument('--reference-root', type=Path, required=True)
    qualify_parser.add_argument('--max-jobs', type=int, default=3)
    qualify_parser.add_argument('--workers', type=int, choices=range(1, 5), default=1)
    qualify_parser.add_argument('--trials', type=int, choices=range(1, 4), default=2)
    qualify_parser.add_argument('--timeout', type=int, default=600)
    qualify_parser.add_argument('--review-reserve-dollars', type=float)
    qualify_parser.add_argument('--pilot-reserve-dollars', type=float)
    verify = commands.add_parser('verify')
    verify.add_argument('bundle', type=Path)
    export = commands.add_parser('export')
    export.add_argument('--output', type=Path, required=True)
    portable = commands.add_parser('verify-export')
    portable.add_argument('directory', type=Path)
    promote = commands.add_parser('promote')
    promote.add_argument('--candidate-id', required=True)
    promote.add_argument('--fingerprint', required=True)
    promote.add_argument('--policy-version', required=True)
    promote.add_argument('--approval', type=Path, required=True)
    promote.add_argument('--manifest', type=Path, required=True)
    recover = commands.add_parser('recover-killed-stage')
    recover.add_argument('--token', required=True)
    recover.add_argument('--reason', required=True)
    uncertain = commands.add_parser('mark-charge-uncertain')
    uncertain.add_argument('--token', required=True)
    uncertain.add_argument('--reason', required=True)
    correction = commands.add_parser('correct-charge')
    correction.add_argument('--token', required=True)
    correction.add_argument('--actual-dollars', type=float, required=True)
    correction.add_argument('--reason', required=True)
    args = parser.parse_args()
    queue = Queue(args.db)
    if args.command == 'enqueue':
        repository = canonical_repository(args.repository)
        if repository not in sources(args.csv):
            parser.error('repository not found in source CSV')
        identity = json.loads(args.identity.read_text())
        ident = queue.enqueue(args.lane, repository, args.max_attempts,
                              identity=identity, task_id=args.task_id)
        receipt = queue.path.parent / 'sources'
        receipt.mkdir(exist_ok=True)
        (receipt / (ident + '.json')).write_text(json.dumps({
            'csv': str(args.csv.resolve()), 'csv_sha256': hashlib.sha256(args.csv.read_bytes()).hexdigest(),
            'name': sources(args.csv)[repository], 'repository': repository,
            'identity': identity, 'identity_sha256': hashlib.sha256(stable_json(identity).encode()).hexdigest()}, indent=2) + '\n')
        print(ident)
    elif args.command == 'configure':
        queue.control.configure(dollar_cap=args.dollar_cap, author_calls=args.author_calls,
            reviewer_calls=args.reviewer_calls, pilot_calls=args.pilot_calls,
            fleet_concurrency=args.fleet_concurrency, storage_bytes=args.storage_bytes,
            approved_by=args.approved_by, policy_version=args.policy_version,
            isolation_receipt=json.loads(args.isolation_receipt.read_text()))
    elif args.command == 'work':
        if args.max_jobs < 1 or args.timeout < 1:
            parser.error('max-jobs and timeout must be positive')
        if not queue.configured():
            parser.error('configure an approved fleet budget before authoring')
        if os.environ.get('GENERAL_ISOLATED_WORKER') != '1':
            parser.error('work must run inside an attested disposable worker (GENERAL_ISOLATED_WORKER=1)')
        def one(lane):
            job = queue.claim(lane=lane)
            if job:
                reservation = stage = None
                try:
                    reservation = queue.control.reserve('author', job['candidate_id'], args.reserve_dollars)
                    stage = queue.control.claim_stage(job['candidate_id'], 'author',
                                                      max(120, args.timeout + 4200), reservation)
                except Exception:
                    queue.release_unstarted(job)
                    raise
                try:
                    execute_job(queue, job, args.timeout, args.runtime)
                    with queue.connect() as db:
                        final = db.execute('SELECT state,result FROM jobs WHERE id=?', (job['id'],)).fetchone()
                    passed = final['state'] == 'needs_review'
                    queue.control.finish_stage(stage, 'passed' if passed else 'failed',
                                               json.loads(final['result'] or '{}'))
                    result = json.loads(final['result'] or '{}')
                    usage = result.get('usage', {})
                    if not usage:
                        queue.control.mark_charge_uncertain(
                            reservation, 'completed author call has no parseable usage event')
                    else:
                        queue.control.reconcile(reservation, luna_usage_cost(usage))
                except BaseException:
                    # A killed process leaves both records open. Expiry fences
                    # stale output and the unreconciled reservation remains spent.
                    raise
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            lanes = ([args.lane] * args.max_jobs if args.lane else
                     [LANES[index % len(LANES)] for index in range(args.max_jobs)])
            list(pool.map(one, lanes))
        print(json.dumps(queue.report(), indent=2))
    elif args.command == 'verify':
        print(verify_record(queue, args.bundle.resolve()))
    elif args.command == 'review':
        if queue.configured() and os.environ.get('GENERAL_ISOLATED_WORKER') != '1':
            parser.error('review must run inside an attested disposable worker')
        return independent_review(queue, args.job, args.timeout, args.reserve_dollars)
    elif args.command == 'recheck':
        return recheck(queue, args.job, runtime=not args.static_only)
    elif args.command == 'retry':
        queue.retry(args.job)
    elif args.command == 'pilot':
        if queue.configured() and os.environ.get('GENERAL_ISOLATED_WORKER') != '1':
            parser.error('pilot must run inside an attested disposable worker')
        from pilot_task import pilot
        return pilot(queue, args.job, args.timeout, args.reserve_dollars)
    elif args.command == 'audit':
        from qa_batch import audit
        return audit(queue, args.reference_root)
    elif args.command == 'qualify':
        if queue.configured() and os.environ.get('GENERAL_ISOLATED_WORKER') != '1':
            parser.error('qualification must run inside attested disposable workers')
        from qualify_batch import qualify
        return qualify(queue, args.reference_root, args.max_jobs, args.workers, args.trials,
                       args.timeout, args.review_reserve_dollars, args.pilot_reserve_dollars)
    elif args.command == 'export':
        export_batch(queue, args.output.resolve())
    elif args.command == 'verify-export':
        print(verify_export(args.directory.resolve()))
    elif args.command == 'promote':
        changed = queue.control.promote(args.candidate_id, args.fingerprint,
            args.policy_version, json.loads(args.approval.read_text()), args.manifest.resolve())
        print('promoted' if changed else 'already promoted')
    elif args.command == 'recover-killed-stage':
        queue.control.recover_killed_stage(args.token, args.reason)
    elif args.command == 'mark-charge-uncertain':
        queue.control.mark_charge_uncertain(args.token, args.reason)
    elif args.command == 'correct-charge':
        queue.control.correct_charge(args.token, args.actual_dollars, args.reason)
    else:
        print(json.dumps(queue.report(), indent=2))


if __name__ == '__main__':
    sys.exit(main())
