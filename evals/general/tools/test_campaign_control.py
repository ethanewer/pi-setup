import json
from pathlib import Path
import sqlite3
import tempfile
import time
import unittest

from generate_tasks import Queue


ISOLATION = {
    'dedicated_disposable_workers': True,
    'scoped_credentials': True,
    'bounded_storage': True,
    'restricted_host_reads': True,
    'controlled_egress': True,
    'no_shared_host_docker': True,
}


def identity(outcome='repair configuration merge', differentiator='nested deletion'):
    return {
        'lane': 'repo', 'repository': 'https://github.com/example/project',
        'revision': 'a' * 40,
        'family': 'configuration repair', 'language': 'python', 'domain': 'developer tools',
        'license': 'MIT',
        'workflow': {
            'outcome': outcome,
            'decisions': ['select merge policy'],
            'deliverables': ['python merge module'],
            'failure_modes': ['nested values are lost'],
            'distinguishers': [differentiator],
            'test_structure': ['property tests and cli integration'],
            'skill_coverage': ['configuration recovery'],
        },
    }


class CampaignControlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.queue = Queue(self.root / 'queue.db')

    def configure(self, **overrides):
        values = dict(dollar_cap=100, author_calls=20, reviewer_calls=20,
                      pilot_calls=40, fleet_concurrency=4, storage_bytes=10_000_000,
                      approved_by='independent-owner', policy_version='qa-v2',
                      isolation_receipt=ISOLATION)
        values.update(overrides)
        self.queue.control.configure(**values)

    def test_same_repository_allows_distinct_workflows_but_retains_rejections(self):
        self.queue.enqueue('repo', identity()['repository'], identity=identity(), task_id='amber-one')
        different = identity('diagnose dependency resolver', 'conflict explanation graph')
        different['workflow'].update(
            decisions=['identify minimal incompatible version set'],
            deliverables=['dependency conflict report'],
            failure_modes=['optional dependency marker is ignored'],
            test_structure=['resolver fixture matrix'],
            skill_coverage=['dependency diagnosis'])
        self.queue.enqueue('repo', different['repository'], identity=different, task_id='amber-two')
        with self.assertRaises(ValueError):
            self.queue.enqueue('repo', identity()['repository'], identity=identity(), task_id='amber-copy')
        report = self.queue.report()
        self.assertEqual(len(report['jobs']), 2)
        self.assertEqual([a['decision'] for a in report['admissions']].count('rejected'), 1)

    def test_semantic_duplicate_is_not_fooled_by_renamed_outcome(self):
        self.queue.enqueue('repo', identity()['repository'], identity=identity(), task_id='amber-one')
        renamed = identity('restore layered settings safely', 'nested deletion')
        # Same source plus the same decision/test/failure shape is rejected even
        # though no instruction text or task name is shared.
        with self.assertRaisesRegex(ValueError, 'semantic workflow duplicate'):
            self.queue.enqueue('repo', renamed['repository'], identity=renamed, task_id='renamed-copy')

    def test_budget_reservation_is_fleet_wide_and_reconciled_once(self):
        self.configure(dollar_cap=3, author_calls=2)
        cid = self.queue.control.admit(identity(), 'amber-one')
        first = self.queue.control.reserve('author', cid, 2)
        with self.assertRaisesRegex(ValueError, 'dollar cap'):
            self.queue.control.reserve('author', cid, 2)
        self.queue.control.reconcile(first, 1)
        second = self.queue.control.reserve('author', cid, 2)
        with self.assertRaises(ValueError):
            self.queue.control.reconcile(first, 1)
        self.assertTrue(second)

    def test_reconciled_charge_correction_is_audited(self):
        self.configure()
        cid = self.queue.control.admit(identity(), 'amber-one')
        token = self.queue.control.reserve('author', cid, 2)
        self.queue.control.reconcile(token, 1)
        self.queue.control.correct_charge(token, 1.25, 'long-context multiplier')
        report = self.queue.report()
        self.assertEqual(report['budget_reservations'][0]['actual_dollars'], 1.25)
        self.assertIn('long-context multiplier', report['operator_events'][-1]['action'])
        with self.assertRaises(ValueError):
            self.queue.control.correct_charge('missing', 1, 'invalid')

    def test_every_stage_is_fenced_after_worker_death(self):
        cid = self.queue.control.admit(identity(), 'amber-one')
        for stage in ('author', 'review', 'build', 'mutation', 'repeat_runtime',
                      'pilot', 'audit', 'promotion'):
            stale = self.queue.control.claim_stage(cid, stage, lease_seconds=-1)
            fresh = self.queue.control.claim_stage(cid, stage, lease_seconds=30)
            with self.assertRaises(RuntimeError):
                self.queue.control.finish_stage(stale, 'passed', {})
            self.queue.control.finish_stage(fresh, 'passed', {'fingerprint': 'f' * 64})

    def test_nested_stage_uses_same_candidate_worker_slot(self):
        self.configure(fleet_concurrency=1)
        first = self.queue.control.admit(identity(), 'amber-one')
        other_identity = identity('repair request routing', 'method precedence')
        other_identity['repository'] = 'https://github.com/example/other'
        second = self.queue.control.admit(other_identity, 'amber-two')
        author = self.queue.control.claim_stage(first, 'author')
        build = self.queue.control.claim_stage(first, 'build')
        with self.assertRaisesRegex(ValueError, 'concurrency cap'):
            self.queue.control.claim_stage(second, 'author')
        with self.assertRaisesRegex(ValueError, 'concurrency cap'):
            self.queue.control.reserve('author', second, 1)
        self.queue.control.finish_stage(build, 'passed', {})
        self.queue.control.finish_stage(author, 'passed', {})

    def test_storage_cap_counts_durable_bytes_without_copying(self):
        self.configure(storage_bytes=10)
        cid = self.queue.control.admit(identity(), 'amber-one')
        bundle = self.root / 'bundle'
        bundle.mkdir()
        (bundle / 'evidence').write_bytes(b'1234567890')
        self.assertEqual(self.queue.control.account_storage(bundle, cid), 10)
        (bundle / 'more').write_bytes(b'x')
        with self.assertRaisesRegex(ValueError, 'storage'):
            self.queue.control.account_storage(bundle, cid)

    def test_configuration_rejects_unisolated_workers(self):
        bad = dict(ISOLATION)
        bad['restricted_host_reads'] = False
        with self.assertRaisesRegex(ValueError, 'isolation'):
            self.configure(isolation_receipt=bad)

    def test_incomplete_or_stale_evidence_cannot_promote(self):
        self.configure()
        cid = self.queue.control.admit(identity(), 'amber-one')
        digest = 'f' * 64
        # Deliberately incomplete work has only runtime evidence, and it is for
        # old bytes. Neither condition may be papered over by human approval.
        claim = self.queue.control.claim_stage(cid, 'repeat_runtime')
        self.queue.control.finish_stage(claim, 'passed', {'fingerprint': 'e' * 64})
        with self.assertRaisesRegex(ValueError, 'fingerprint-bound stages'):
            self.queue.control.promote(cid, digest, 'qa-v2',
                {'status': 'approved', 'independent_reviewer': 'release-owner'},
                self.root / 'manifest.json')

    def test_promotion_requires_current_fingerprint_and_is_idempotent(self):
        self.configure()
        cid = self.queue.control.admit(identity(), 'amber-one')
        digest = 'f' * 64
        for stage in ('review', 'mutation', 'repeat_runtime', 'pilot', 'audit'):
            claim = self.queue.control.claim_stage(cid, stage)
            result = {'fingerprint': digest}
            if stage == 'review':
                result = {'author_fingerprint': digest}
            if stage == 'audit':
                result = {'fingerprints': {'amber-one': digest}}
            self.queue.control.finish_stage(claim, 'passed', result)
        manifest = self.root / 'manifest.json'
        approval = {'status': 'approved', 'independent_reviewer': 'release-owner'}
        self.assertTrue(self.queue.control.promote(cid, digest, 'qa-v2', approval, manifest))
        self.assertFalse(self.queue.control.promote(cid, digest, 'qa-v2', approval, manifest))
        self.assertEqual(len(json.loads(manifest.read_text())), 1)

    def test_legacy_schema_migrates_without_changing_ids_or_results(self):
        path = self.root / 'legacy.db'
        db = sqlite3.connect(path)
        db.execute('''CREATE TABLE jobs (id TEXT PRIMARY KEY,lane TEXT NOT NULL,
                    repository TEXT NOT NULL UNIQUE,state TEXT NOT NULL,attempt INTEGER NOT NULL,
                    max_attempts INTEGER NOT NULL,token TEXT,lease REAL,result TEXT)''')
        db.execute('INSERT INTO jobs VALUES(?,?,?,?,?,?,?,?,?)',
                   ('repo-old', 'repo', 'https://github.com/a/b', 'failed', 2, 3,
                    None, None, '{"old":true}'))
        db.commit()
        db.close()
        migrated = Queue(path).report()['jobs'][0]
        self.assertEqual((migrated['id'], migrated['state'], migrated['result']),
                         ('repo-old', 'failed', '{"old":true}'))


if __name__ == '__main__':
    unittest.main()
