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
import subprocess
import sys
import threading
import time
import uuid
from urllib.parse import urlsplit

from author_task import validate, fingerprint
from lint_tasks import CATEGORIES, RUBRIC_KEYS

ROOT = Path(__file__).resolve().parents[1]
MODEL = 'gpt-5.6-luna'
EFFORT = 'medium'
LANES = ('skills', 'repo', 'pr-issue')


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
    for key, expected in (('schema_version', 1), ('pipeline', job['lane']), ('task_id', job['id'])):
        if key in candidate and candidate[key] != expected:
            raise ValueError(f'candidate {key} conflicts with queued job')
        candidate[key] = expected
    candidate.setdefault('author', 'codex-cli-gpt-5.6-luna-medium')
    source = candidate.get('source')
    if isinstance(source, dict):
        repository = canonical_repository(source.get('repository', job['repository']))
        if repository != job['repository']:
            raise ValueError('candidate repository conflicts with queued source')
        source['repository'] = repository
    return validate(candidate)


class Queue:
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, lane TEXT NOT NULL, repository TEXT NOT NULL UNIQUE,
                    state TEXT NOT NULL DEFAULT 'queued', attempt INTEGER NOT NULL DEFAULT 0,
                    max_attempts INTEGER NOT NULL, token TEXT, lease REAL, result TEXT);
                CREATE TABLE IF NOT EXISTS attempts (
                    job TEXT, number INTEGER, token TEXT UNIQUE, started REAL, finished REAL,
                    state TEXT, result TEXT, PRIMARY KEY(job, number));
                CREATE TABLE IF NOT EXISTS reviews (
                    id TEXT PRIMARY KEY, job TEXT, result TEXT);
                CREATE TABLE IF NOT EXISTS checks (
                    id TEXT PRIMARY KEY, job TEXT, result TEXT);
                CREATE TABLE IF NOT EXISTS operator_events (
                    at REAL, job TEXT, action TEXT);
            ''')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(str(self.path), timeout=30)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def enqueue(self, lane, repository, max_attempts=2):
        if lane not in LANES or not 1 <= max_attempts <= 5:
            raise ValueError('invalid lane or attempt limit')
        repository = canonical_repository(repository)
        ident = lane + '-' + hashlib.sha256(repository.encode()).hexdigest()[:12]
        with self.connect() as db:
            db.execute('INSERT INTO jobs(id,lane,repository,max_attempts) VALUES(?,?,?,?)',
                       (ident, lane, repository, max_attempts))
        return ident

    def claim(self, seconds=120):
        now = time.time()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            expired = db.execute("SELECT * FROM jobs WHERE state='running' AND lease<?", (now,)).fetchall()
            for job in expired:
                db.execute("UPDATE attempts SET state='lease_expired',finished=? WHERE token=? AND finished IS NULL", (now, job['token']))
                db.execute("UPDATE jobs SET state=?,token=NULL WHERE id=?", (
                    'failed' if job['attempt'] >= job['max_attempts'] else 'queued', job['id']))
            row = db.execute("SELECT * FROM jobs WHERE state='queued' ORDER BY id LIMIT 1").fetchone()
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
        counts = {lane: {} for lane in LANES}
        usage = {}
        for job in jobs:
            lane = counts[job['lane']]
            lane[job['state']] = lane.get(job['state'], 0) + 1
        for attempt in attempts + reviews + checks:
            for key, value in json.loads(attempt['result'] or '{}').get('usage', {}).items():
                usage[key] = usage.get(key, 0) + value
        return {'model': MODEL, 'reasoning_effort': EFFORT, 'counts': counts,
                'usage': usage, 'jobs': jobs, 'attempts': attempts, 'reviews': reviews, 'checks': checks,
                'operator_events': events,
                'usage_caveat': 'Completed CLI turns only; interrupted calls may be unmetered. No dollar estimate without configured rates.'}


def run_process(command, cwd, stdout, stderr, timeout, lost, stdin=None):
    """Kill the whole local process group on timeout or lost lease."""
    environment = os.environ.copy()
    owner = None
    if str(ROOT / 'tools/qa_task.py') in command:
        owner = uuid.uuid4().hex
        environment['GENERAL_QA_RUN_ID'] = owner
    with stdout.open('w') as out, stderr.open('w') as err:
        process = subprocess.Popen(command, cwd=str(cwd), stdin=stdin,
                                   stdout=out, stderr=err, start_new_session=True, env=environment)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                if lost.wait(0.25) or time.monotonic() >= deadline:
                    raise TimeoutError('stage deadline exceeded or lease lost')
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


def recheck(queue, ident):
    """Rerun trusted QA on unchanged generated content, without paying to reauthor."""
    with queue.connect() as db:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
    if job is None or job['state'] not in ('failed', 'needs_review'):
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
              'thread_id': original['thread_id'], 'kind': 'qa_recheck', 'usage': {},
              'model': original['model'], 'reasoning_effort': original['reasoning_effort']}
    try:
        check_skill_sources(work, candidate)
        if not any(p.is_file() for p in (work / 'receipts').rglob('*')):
            raise ValueError('source receipts are missing')
        duplicates = near_duplicates(work / 'tasks' / ident, (ROOT / 'tasks').iterdir())
        (output / 'duplicates.json').write_text(json.dumps(duplicates, indent=2) + '\n')
        if duplicates:
            raise ValueError('near-duplicate instruction detected')
        command = [sys.executable, str(ROOT / 'tools/qa_task.py'), '--candidate', str(work / 'candidate.json'),
                   '--suite-root', str(work), '--output-root', str(output / 'qa'), '--runtime-backend', 'docker', '--runtime-only']
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
    with queue.connect() as db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('INSERT INTO checks VALUES(?,?,?)', (check_id, ident, json.dumps(result)))
        changed = db.execute('UPDATE jobs SET state=?,result=? WHERE id=? AND result=?',
                   (result['status'], json.dumps(result), ident, job['result'])).rowcount
        if changed != 1:
            raise RuntimeError('job changed during recheck')
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


def independent_review(queue, ident, timeout):
    with queue.connect() as db:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (ident,)).fetchone()
    if job is None or job['state'] != 'needs_review':
        raise ValueError('review requires a draft that passed requested QA controls')
    author = json.loads(job['result'])
    bundle = Path(author['bundle'])
    verify_record(queue, bundle)
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
    with queue.connect() as db:
        db.execute('INSERT INTO reviews VALUES(?,?,?)', (review_id, ident, json.dumps(result)))
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
    prompt = f'''Create ONE original general evaluation task via the {job['lane']} lane.
Source repository: {job['repository']}. Task id: {job['id']}.
Read contract/README.md and contract/{job['lane']}.md. Use no benchmarks or existing evaluation tasks as sources.
Inspect upstream code/documentation and record actual immutable commits, license and baseline commands/results in receipts/.
For pr-issue choose a real bounded upstream issue/PR; verify base and reproduction, keep fix/history out of task image.
For skills FIRST create a genuinely reusable skill in skills/<name>/SKILL.md with YAML name/description,
concise repository-specific workflow guidance, then apply it to a new scenario. Record skill path and SHA256.
Write candidate.json satisfying contract/author_task.py validate(), with pipeline={job['lane']}, schema_version=1,
author=codex-cli-gpt-5.6-luna-medium. Use the exact task id above and source.repository above.
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
        code = run_process(qa, work, bundle / 'qa.log', bundle / 'qa.stderr', 3600, lost)
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
    worker = commands.add_parser('work')
    worker.add_argument('--workers', type=int, choices=range(1, 5), default=1)
    worker.add_argument('--max-jobs', type=int, default=3, help='hard limit on author CLI invocations in this run')
    worker.add_argument('--timeout', type=int, default=1200)
    worker.add_argument('--runtime', action='store_true')
    commands.add_parser('report')
    review = commands.add_parser('review')
    review.add_argument('--job', required=True)
    review.add_argument('--timeout', type=int, default=600)
    check = commands.add_parser('recheck')
    check.add_argument('--job', required=True)
    retry = commands.add_parser('retry')
    retry.add_argument('--job', required=True)
    pilot_parser = commands.add_parser('pilot')
    pilot_parser.add_argument('--job', required=True)
    pilot_parser.add_argument('--timeout', type=int, default=600)
    audit_parser = commands.add_parser('audit')
    audit_parser.add_argument('--reference-root', type=Path, required=True)
    qualify_parser = commands.add_parser('qualify')
    qualify_parser.add_argument('--reference-root', type=Path, required=True)
    qualify_parser.add_argument('--max-jobs', type=int, default=3)
    qualify_parser.add_argument('--workers', type=int, choices=range(1, 5), default=1)
    qualify_parser.add_argument('--trials', type=int, choices=range(1, 4), default=2)
    qualify_parser.add_argument('--timeout', type=int, default=600)
    verify = commands.add_parser('verify')
    verify.add_argument('bundle', type=Path)
    export = commands.add_parser('export')
    export.add_argument('--output', type=Path, required=True)
    portable = commands.add_parser('verify-export')
    portable.add_argument('directory', type=Path)
    args = parser.parse_args()
    queue = Queue(args.db)
    if args.command == 'enqueue':
        repository = canonical_repository(args.repository)
        if repository not in sources(args.csv):
            parser.error('repository not found in source CSV')
        ident = queue.enqueue(args.lane, repository, args.max_attempts)
        receipt = queue.path.parent / 'sources'
        receipt.mkdir(exist_ok=True)
        (receipt / (ident + '.json')).write_text(json.dumps({
            'csv': str(args.csv.resolve()), 'csv_sha256': hashlib.sha256(args.csv.read_bytes()).hexdigest(),
            'name': sources(args.csv)[repository], 'repository': repository}, indent=2) + '\n')
        print(ident)
    elif args.command == 'work':
        if args.max_jobs < 1 or args.timeout < 1:
            parser.error('max-jobs and timeout must be positive')
        def one(_):
            job = queue.claim()
            if job:
                execute_job(queue, job, args.timeout, args.runtime)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            list(pool.map(one, range(args.max_jobs)))
        print(json.dumps(queue.report(), indent=2))
    elif args.command == 'verify':
        print(verify_record(queue, args.bundle.resolve()))
    elif args.command == 'review':
        return independent_review(queue, args.job, args.timeout)
    elif args.command == 'recheck':
        return recheck(queue, args.job)
    elif args.command == 'retry':
        queue.retry(args.job)
    elif args.command == 'pilot':
        from pilot_task import pilot
        return pilot(queue, args.job, args.timeout)
    elif args.command == 'audit':
        from qa_batch import audit
        return audit(queue, args.reference_root)
    elif args.command == 'qualify':
        from qualify_batch import qualify
        return qualify(queue, args.reference_root, args.max_jobs, args.workers, args.trials, args.timeout)
    elif args.command == 'export':
        export_batch(queue, args.output.resolve())
    elif args.command == 'verify-export':
        print(verify_export(args.directory.resolve()))
    else:
        print(json.dumps(queue.report(), indent=2))


if __name__ == '__main__':
    sys.exit(main())
