import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from generate_tasks import Queue
from qualify_batch import qualify


class QualificationTests(unittest.TestCase):
    def test_failed_review_skips_expensive_controls_and_never_promotes(self):
        with tempfile.TemporaryDirectory() as directory:
            queue = Queue(Path(directory) / 'queue.db')
            ident = queue.enqueue('repo', 'https://github.com/a/b')
            queue.finish(queue.claim(), 'needs_review', {})

            def review(*args):
                with queue.connect() as db:
                    db.execute('INSERT INTO reviews VALUES(?,?,?)', ('review', ident, json.dumps({'review': {'verdict': 'revise'}})))
                return 0

            with patch('qualify_batch.independent_review', side_effect=review), patch('qualify_batch.recheck') as repeat, patch('qualify_batch.pilot') as pilot, patch('qualify_batch.audit', return_value=0) as audit:
                self.assertEqual(qualify(queue, Path(directory)), 1)
                repeat.assert_not_called()
                pilot.assert_not_called()
                audit.assert_called_once_with(queue, Path(directory), [ident])
            self.assertEqual(queue.report()['jobs'][0]['state'], 'needs_review')


if __name__ == '__main__':
    unittest.main()
