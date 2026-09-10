import sys
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))

from enrichd.cache import ProfileCache
from enrichd.embed import build_digest
from enrichd import protocol

DAY = "2026-04-27"


class ProfileCacheTests(unittest.TestCase):
    def test_fetch_memoises(self):
        cache = ProfileCache()
        d1 = cache.fetch("Acct 001", DAY)
        d2 = cache.fetch("Acct 001", DAY)
        self.assertIs(d1, d2)
        self.assertEqual(len(cache), 1)

    def test_digest_is_pure(self):
        cache = ProfileCache()
        got = cache.fetch(" Acct 001~b9 ", DAY)
        want = build_digest(protocol.normalise_client(" Acct 001~b9 "), DAY)
        self.assertEqual(got, want)

    def test_day_is_part_of_the_key(self):
        cache = ProfileCache()
        d1 = cache.fetch("Acct 001", "2026-04-27")
        d2 = cache.fetch("Acct 001", "2026-04-28")
        self.assertIsNot(d1, d2)
        self.assertEqual(len(cache), 2)

    def test_max_entries_bounds_the_store(self):
        cache = ProfileCache(max_entries=2)
        d1 = cache.fetch("Acct 001", DAY)
        cache.fetch("Acct 002", DAY)
        cache.fetch("Acct 003", DAY)
        self.assertLessEqual(len(cache), 2)
        # eviction must not change values: entries are pure functions
        rebuilt = cache.fetch("Acct 001", DAY)
        self.assertEqual(rebuilt, d1)

    def test_hits_and_misses_are_counted(self):
        cache = ProfileCache()
        cache.fetch("Acct 001", DAY)
        cache.fetch("Acct 001", DAY)
        self.assertEqual(cache.hits, 1)
        self.assertEqual(cache.misses, 1)


if __name__ == "__main__":
    unittest.main()
