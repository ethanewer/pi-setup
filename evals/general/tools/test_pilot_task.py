import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from generate_tasks import Queue, seal, verify_seal
from pilot_task import pilot


class PilotTests(unittest.TestCase):
    def test_tests_only_arrive_after_agent_and_no_oracle_is_supplied(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            queue = Queue(root / 'queue.db')
            ident = queue.enqueue('repo', 'https://github.com/a/b')
            job = queue.claim()
            bundle = root / 'source'
            task = bundle / 'workspace/tasks' / ident
            (task / 'environment').mkdir(parents=True)
            (task / 'tests').mkdir()
            (task / 'instruction.md').write_text('Synthetic pilot transport fixture.')
            (task / 'task.toml').write_text('[environment]\nnetwork_mode="no-network"\n[metadata]\ndeliverables=[]\n')
            (bundle / 'seal.json').write_text(json.dumps(seal(bundle)))
            queue.finish(job, 'needs_review', {'bundle': str(bundle), 'fingerprint': 'fixture', 'seal_sha256': verify_seal(bundle)})
            calls = []

            def command(args, **kwargs):
                calls.append(args)
                if args[:2] == ['docker', 'exec']:
                    verifier = next((root / 'pilots' / ident).glob('*/verifier'))
                    (verifier / 'reward.txt').write_text('1')
                return subprocess.CompletedProcess(args, 0)

            def agent(args, cwd, stdout, stderr, timeout, lost, stdin=None):
                calls.append(['AGENT'])
                self.assertEqual(sorted(p.name for p in cwd.iterdir()), ['instruction.md', 'prompt.txt'])
                self.assertFalse(any('/tests' in str(arg) for call in calls for arg in call))
                stdout.write_text('{"type":"thread.started","thread_id":"fixture"}\n')
                stderr.write_text('')
                return 0

            with patch('pilot_task.subprocess.run', side_effect=command), patch('pilot_task.subprocess.check_output', return_value='sha256:fixture'), patch('pilot_task.run_process', side_effect=agent), patch('pilot_task.session_context', return_value={}):
                self.assertEqual(pilot(queue, ident, 10), 0)
            copied = next(i for i, call in enumerate(calls) if call[:2] == ['docker', 'cp'])
            self.assertGreater(copied, calls.index(['AGENT']))
            self.assertFalse(any('/solution' in str(arg) for call in calls for arg in call))
            result = json.loads(queue.report()['checks'][0]['result'])
            self.assertEqual(result['reward'], 1)
            self.assertEqual(queue.report()['jobs'][0]['state'], 'needs_review')


if __name__ == '__main__':
    unittest.main()
