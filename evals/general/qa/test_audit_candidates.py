import random
import unittest

from audit_candidates import audit, scoped_blocks


class ScopedIndexTests(unittest.TestCase):
    def test_reviewed_decimal_primitive_is_narrow(self):
        primitive = (b'0123456789' * 7)[:64]
        self.assertTrue(audit.boilerplate_block(primitive))
        self.assertFalse(audit.boilerplate_block(b'UNIQUE TASK OBJECTIVE ' + primitive))

    def test_retained_blocks_match_full_audit_exactly(self):
        rng = random.Random(17)
        candidate = bytes(rng.randrange(256) for _ in range(2048))
        wanted = {entry[1] for entry in audit.block_digests(candidate)}
        reference = bytes(rng.randrange(256) for _ in range(256)) + candidate + b' unrelated ' * 200
        expected = [entry for entry in audit.block_digests(reference) if entry[1] in wanted]
        self.assertTrue(expected)
        self.assertEqual(list(scoped_blocks(reference, wanted)), expected)

    def test_candidate_signatures_are_not_removed(self):
        candidate = b'#!/bin/bash\nset -euo pipefail\n' * 80
        original = list(audit.block_digests(candidate))
        self.assertEqual(list(scoped_blocks(candidate, {entry[1] for entry in original})), original)


if __name__ == '__main__':
    unittest.main()
