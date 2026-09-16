"""Regression tests for source routing and fail-closed acceptance."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from author_task import validate, fingerprint
from qa_task import REVIEW_GATES, review_errors, run_controls
import qa_task


class AuthoringTests(unittest.TestCase):
    def candidate(self, pipeline='skills'):
        source = {'benchmark_derived': False, 'license': 'MIT'}
        if pipeline == 'skills':
            source.update(skill_paths=['skill@revision'], scenario='realistic incident')
        else:
            source.update(repository='https://example.org/project', base_commit='a' * 40,
                          workflow='repair configuration', reference='issue/123',
                          reproduction='run command: expected success, observed failure')
        return dict(schema_version=1, pipeline=pipeline, task_id='sample-task',
                    author='alice', objective='recover configuration',
                    acceptance=['service starts'], skills=['diagnosis'], source=source)

    def test_all_frontends_share_contract(self):
        for pipeline in ('skills', 'repo', 'pr-issue'):
            self.assertEqual(validate(self.candidate(pipeline))['pipeline'], pipeline)

    def test_rejects_invalid_sources_and_paths(self):
        for change in ({'task_id': '../escape'}, {'pipeline': 'unknown'}, {'skills': 'string'}):
            candidate = self.candidate()
            candidate.update(change)
            with self.assertRaises(ValueError):
                validate(candidate)
        for pipeline, field in (('skills', 'skill_paths'), ('repo', 'base_commit'), ('pr-issue', 'reproduction')):
            candidate = self.candidate(pipeline)
            del candidate['source'][field]
            with self.assertRaises(ValueError):
                validate(candidate)
        candidate = self.candidate()
        candidate['source']['benchmark_derived'] = True
        with self.assertRaises(ValueError):
            validate(candidate)

    def test_content_and_permissions_invalidate_review(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory)
            file = task / 'solve.sh'
            file.write_text('original')
            original = fingerprint(task, self.candidate())
            file.write_text('changed')
            changed = fingerprint(task, self.candidate())
            self.assertNotEqual(original, changed)
            file.chmod(0o755)
            self.assertNotEqual(changed, fingerprint(task, self.candidate()))
            (task / 'link').symlink_to(file)
            with self.assertRaises(ValueError):
                fingerprint(task, self.candidate())

    def test_reviews_fail_closed(self):
        review = {'fingerprint': 'digest', **{gate: {'status': 'pass', 'reviewer': 'bob', 'evidence': 'log'} for gate in REVIEW_GATES}}
        self.assertEqual(review_errors(review, 'digest', 'alice'), [])
        self.assertTrue(review_errors(review, 'stale', 'alice'))
        for gate in REVIEW_GATES:
            bad = copy.deepcopy(review)
            del bad[gate]
            self.assertTrue(review_errors(bad, 'digest', 'alice'))
        self.assertTrue(review_errors(review, 'digest', 'bob'))

    def test_controls_require_success_and_unique_correct_reward(self):
        for returncode, reward_count, expected in ((0, 1, False), (1, 1, True), (0, 0, True), (0, 2, True)):
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory)
                def fake_run(command, **kwargs):
                    agent = command[command.index('-a') + 1]
                    job = Path(command[-1])
                    for index in range(reward_count):
                        reward = job / str(index) / 'reward.txt'
                        reward.parent.mkdir(parents=True)
                        reward.write_text('1.0' if agent == 'oracle' else '0.0')
                    return subprocess.CompletedProcess(command, returncode)
                with patch('qa_task.subprocess.run', side_effect=fake_run):
                    self.assertEqual(bool(run_controls(Path('task'), output)), expected)

    def test_control_missing_tool_blocks_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch('qa_task.subprocess.run', side_effect=FileNotFoundError('harbor')):
                self.assertEqual(len(run_controls(Path('task'), Path(directory))), 2)

    def test_runtime_only_collects_evidence_without_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tasks/sample-task').mkdir(parents=True)
            candidate = root / 'candidate.json'
            candidate.write_text(json.dumps(self.candidate()))
            argv = ['qa_task.py', '--candidate', str(candidate), '--runtime-only',
                    '--output-root', str(root / 'results')]
            with patch.object(qa_task, 'ROOT', root), patch('sys.argv', argv), \
                 patch('qa_task.subprocess.run', return_value=subprocess.CompletedProcess([], 0)), \
                 patch('qa_task.run_controls', return_value=[]) as controls:
                self.assertEqual(qa_task.main(), 0)
                controls.assert_called_once()
            report = json.loads(next((root / 'results').glob('*/report.json')).read_text())
            self.assertEqual(report['status'], 'draft')
            self.assertEqual(report['mode'], 'runtime')

    def test_docker_controls_enforce_network_and_reject_failed_oracle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            task = root / 'task'
            task.mkdir()
            (task / 'task.toml').write_text('[environment]\nnetwork_mode = "no-network"\n')
            output = root / 'results'
            output.mkdir()
            calls = []
            def execute(command, **kwargs):
                if command[1] == 'run':
                    calls.append(command)
                    self.assertEqual(command[command.index('--network') + 1], 'none')
                    mount = next(x for x in command if x.endswith('target=/logs/verifier'))
                    job = Path(mount.split('source=', 1)[1].split(',target=', 1)[0])
                    is_oracle = job.name == 'oracle'
                    (job / 'reward.txt').write_text('1' if is_oracle else '0')
                    return subprocess.CompletedProcess(command, 1 if is_oracle else 0)
                return subprocess.CompletedProcess(command, 0)
            with patch('qa_task.subprocess.run', side_effect=execute), \
                 patch('qa_task.subprocess.check_output', return_value='sha256:test'):
                errors = qa_task.run_docker_controls(task, output)
            self.assertEqual(len(errors), 1)
            self.assertTrue(errors[0].startswith('oracle:'))
            self.assertEqual(len(calls), 2)
            self.assertFalse(any('target=/solution' in arg for arg in calls[1]))


if __name__ == '__main__':
    unittest.main()
