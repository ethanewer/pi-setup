import concurrent.futures
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch
import hashlib

from generate_tasks import (Queue, canonical_repository, seal, verify_seal,
                            usage_from_events, run_process, verify_record,
                            instruction_shingles, near_duplicates, check_skill_sources,
                            execute_job, export_batch, verify_export, session_context,
                            normalize_candidate, directory_file_bytes)


class FactoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.queue = Queue(self.root / 'queue.db')

    def test_canonical_sources(self):
        self.assertEqual(canonical_repository('https://github.com/Pallets/Click.git/'),
                         'https://github.com/pallets/click')
        for url in ('https://evil.com/a/b', 'https://github.com/a/b/issues',
                    'https://user@github.com/a/b', 'http://github.com/a/b',
                    'https://github.com/a/b?x=1'):
            with self.assertRaises(ValueError):
                canonical_repository(url)

    def test_storage_scan_ignores_broken_symlinks(self):
        scratch = self.root / 'scratch'
        scratch.mkdir()
        (scratch / 'data').write_bytes(b'1234')
        (scratch / 'vanished').symlink_to(scratch / 'missing')
        self.assertEqual(directory_file_bytes(scratch), 4)

    def test_duplicate_source_across_lanes(self):
        self.queue.enqueue('skills', 'https://github.com/a/b')
        with self.assertRaises(sqlite3.IntegrityError):
            self.queue.enqueue('repo', 'https://github.com/A/B.git')

    def test_queue_owns_mechanical_metadata_but_rejects_conflicts(self):
        job = {'id': 'example-task', 'lane': 'skills', 'repository': 'https://github.com/a/b'}
        raw = {'objective': 'fixture', 'acceptance': ['fixture'], 'skills': ['fixture'],
               'source': {'benchmark_derived': False, 'license': 'MIT', 'scenario': 'fixture',
                          'skill_paths': ['skills/fixture/SKILL.md@revision']}}
        normalized = normalize_candidate(raw, job)
        self.assertEqual(normalized['source']['repository'], job['repository'])
        self.assertNotIn('repository', raw['source'])
        raw['task_id'] = 'different-task'
        with self.assertRaises(ValueError):
            normalize_candidate(raw, job)

    def test_concurrent_claims_unique(self):
        for i in range(20):
            self.queue.enqueue('repo', f'https://github.com/a/b{i}')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            jobs = list(pool.map(lambda _: self.queue.claim(), range(24)))
        ids = [job['id'] for job in jobs if job]
        self.assertEqual(len(ids), 20)
        self.assertEqual(len(set(ids)), 20)

    def test_expiration_fences_old_worker_and_bounds_retries(self):
        self.queue.enqueue('repo', 'https://github.com/a/b', max_attempts=2)
        old = self.queue.claim(seconds=-1)
        self.assertFalse(self.queue.heartbeat(old))
        new = self.queue.claim(seconds=-1)
        self.assertEqual(new['attempt'], 2)
        with self.assertRaises(RuntimeError):
            self.queue.finish(old, 'needs_review', {})
        self.assertIsNone(self.queue.claim())
        self.assertEqual(self.queue.report()['jobs'][0]['state'], 'failed')

    def test_worker_cannot_accept(self):
        self.queue.enqueue('repo', 'https://github.com/a/b')
        job = self.queue.claim()
        with self.assertRaises(ValueError):
            self.queue.finish(job, 'accepted', {})
        self.queue.finish(job, 'needs_review', {'usage': {'input_tokens': 20}})
        self.assertEqual(self.queue.report()['usage']['input_tokens'], 20)
        self.assertIsNone(self.queue.claim())

    def test_seal_detects_content_permissions_and_added_files(self):
        bundle = self.root / 'bundle'
        bundle.mkdir()
        path = bundle / 'review.json'
        path.write_text('{}')
        (bundle / 'seal.json').write_text(json.dumps(seal(bundle)))
        verify_seal(bundle)
        path.chmod(0o700)
        with self.assertRaises(ValueError):
            verify_seal(bundle)
        (bundle / 'seal.json').write_text(json.dumps(seal(bundle)))
        path.write_text('{"status":"pass"}')
        with self.assertRaises(ValueError):
            verify_seal(bundle)
        (bundle / 'seal.json').write_text(json.dumps(seal(bundle)))
        (bundle / 'extra').write_text('extra')
        with self.assertRaises(ValueError):
            verify_seal(bundle)

    def test_symlinks_rejected(self):
        (self.root / 'link').symlink_to('/tmp')
        with self.assertRaises(ValueError):
            seal(self.root)

    def test_usage_handles_truncated_last_event(self):
        path = self.root / 'events'
        path.write_text('{"type":"thread.started","thread_id":"abc"}\n'
                        '{"type":"turn.completed","usage":{"input_tokens":12}}\n{')
        self.assertEqual(usage_from_events(path), ({'input_tokens': 12}, 'abc'))

    def test_process_timeout(self):
        import sys
        with self.assertRaises(TimeoutError):
            run_process([sys.executable, '-c', 'import time; time.sleep(30)'], self.root,
                        self.root / 'out', self.root / 'err', 0.1, threading.Event())

    def test_skill_hash_and_path(self):
        folder = self.root / 'skills/example'
        folder.mkdir(parents=True)
        path = folder / 'SKILL.md'
        path.write_text('---\nname: example\ndescription: Example workflow\n---\n')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        candidate = {'pipeline': 'skills', 'source': {'skill_paths': ['skills/example/SKILL.md@' + digest]}}
        check_skill_sources(self.root, candidate)
        path.write_text('changed')
        with self.assertRaises(ValueError):
            check_skill_sources(self.root, candidate)
        candidate['source']['skill_paths'] = ['../outside@' + digest]
        with self.assertRaises(ValueError):
            check_skill_sources(self.root, candidate)

    def test_near_duplicate_behavior(self):
        first, second = self.root / 'one', self.root / 'two'
        first.mkdir()
        second.mkdir()
        text = 'Implement a robust configuration loader preserving nested defaults and rejecting malformed records.'
        (first / 'instruction.md').write_text(text)
        (second / 'instruction.md').write_text(text.upper())
        self.assertEqual(near_duplicates(first, [second])[0]['similarity'], 1)
        (second / 'instruction.md').write_text('Diagnose offline compiler linker failures using supplied binary objects.')
        self.assertEqual(near_duplicates(first, [second]), [])

    def test_scratch_symlinks_not_evidence(self):
        scratch = self.root / 'workspace/.venv'
        scratch.mkdir(parents=True)
        (scratch / 'python').symlink_to('/usr/bin/python3')
        self.assertFalse(any('.venv' in name for name in seal(self.root)))

    def test_operator_retry_is_bounded_and_recorded(self):
        ident = self.queue.enqueue('repo', 'https://github.com/a/b', max_attempts=1)
        for attempt in range(1, 6):
            job = self.queue.claim()
            self.assertEqual(job['attempt'], attempt)
            self.queue.finish(job, 'failed', {})
            if attempt < 5:
                self.queue.retry(ident)
        with self.assertRaises(ValueError):
            self.queue.retry(ident)
        self.assertEqual(len(self.queue.report()['operator_events']), 4)

    def test_recorded_model_must_match(self):
        thread = 'a' * 8 + '-' + 'b' * 4 + '-' + 'c' * 4 + '-' + 'd' * 4 + '-' + 'e' * 12
        directory = self.root / 'sessions/2026/09/15'
        directory.mkdir(parents=True)
        path = directory / ('rollout-test-' + thread + '.jsonl')
        path.write_text(json.dumps({'type': 'turn_context', 'payload': {'model': 'gpt-5.6-luna', 'effort': 'medium'}}) + '\n')
        with patch.dict('os.environ', {'CODEX_HOME': str(self.root)}):
            self.assertEqual(session_context(thread)['contexts'][0]['effort'], 'medium')
            path.write_text(json.dumps({'type': 'turn_context', 'payload': {'model': 'different', 'effort': 'medium'}}) + '\n')
            with self.assertRaises(ValueError):
                session_context(thread)

    def test_portable_export_preserves_and_verifies_evidence(self):
        self.queue.enqueue('repo', 'https://github.com/a/b')
        job = self.queue.claim()
        bundle = self.root / 'runs' / job['id'] / job['token']
        bundle.mkdir(parents=True)
        (bundle / 'result.json').write_text('{}')
        (bundle / 'seal.json').write_text(json.dumps(seal(bundle)))
        self.queue.finish(job, 'needs_review', {'bundle': str(bundle), 'seal_sha256': verify_seal(bundle)})
        (self.root / 'sources').mkdir()
        export = self.root / 'portable'
        export_batch(self.queue, export)
        self.assertEqual(verify_export(export), 1)
        (export / bundle.relative_to(self.root) / 'result.json').write_text('changed')
        with self.assertRaises(ValueError):
            verify_export(export)

    def test_all_lanes_use_same_pinned_cli_and_qa(self):
        for lane in ('skills', 'repo', 'pr-issue'):
            self.queue.enqueue(lane, f'https://github.com/example/{lane}', max_attempts=1)
            job = self.queue.claim()
            calls = []

            def fake(command, cwd, stdout, stderr, timeout, lost, stdin=None):
                calls.append(command)
                stdout.write_text('')
                stderr.write_text('')
                if command[0] != 'codex':
                    return 0
                stdout.write_text('{"type":"thread.started","thread_id":"new-session"}\n'
                                  '{"type":"turn.completed","usage":{"input_tokens":11}}\n')
                source = {'repository': job['repository'], 'benchmark_derived': False,
                          'base_commit': 'a' * 40, 'license': 'MIT', 'workflow': 'fixture',
                          'reference': 'https://github.com/example/pr-issue/issues/1',
                          'reproduction': 'fixture', 'scenario': 'fixture'}
                if lane == 'skills':
                    skill = cwd / 'skills/SKILL.md'
                    skill.write_text('---\nname: fixture\ndescription: Test fixture\n---\n')
                    source['skill_paths'] = ['skills/SKILL.md@' + hashlib.sha256(skill.read_bytes()).hexdigest()]
                candidate = {'schema_version': 1, 'pipeline': lane, 'task_id': job['id'],
                             'author': 'fixture', 'objective': 'fixture', 'acceptance': ['fixture'],
                             'skills': ['fixture'], 'source': source}
                (cwd / 'candidate.json').write_text(json.dumps(candidate))
                (cwd / 'receipts/source.txt').write_text('fixture')
                task = cwd / 'tasks' / job['id']
                task.mkdir()
                (task / 'instruction.md').write_text('fixture')
                return 0

            with patch('generate_tasks.run_process', side_effect=fake), patch('generate_tasks.near_duplicates', return_value=[]), patch('generate_tasks.session_context', return_value={}):
                execute_job(self.queue, job, 10, True)
            self.assertIn('gpt-5.6-luna', calls[0])
            self.assertIn('model_reasoning_effort="medium"', calls[0])
            self.assertIn('--suite-root', calls[1])
            self.assertIn('--runtime-only', calls[1])
            record = next(row for row in self.queue.report()['jobs'] if row['id'] == job['id'])
            self.assertEqual(record['state'], 'needs_review')
            bundle = Path(json.loads(record['result'])['bundle'])
            verify_record(self.queue, bundle)
            # Replacing both a file AND its adjacent seal cannot fool ledger verification.
            (bundle / 'qa.log').write_text('tampered')
            (bundle / 'seal.json').write_text(json.dumps(seal(bundle)))
            with self.assertRaises(ValueError):
                verify_record(self.queue, bundle)


if __name__ == '__main__':
    unittest.main()
