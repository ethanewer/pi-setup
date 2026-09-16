import sys
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))

from enrichd import protocol


class NormaliseTests(unittest.TestCase):
    def test_canonical_forms(self):
        self.assertEqual(protocol.normalise_client("Acct 001"), "acct 001")
        self.assertEqual(protocol.normalise_client("ACCT 001 "), "acct 001")
        self.assertEqual(protocol.normalise_client(" acct   001"), "acct 001")
        self.assertEqual(protocol.normalise_client("Acct 001~b7"), "acct 001")
        self.assertEqual(protocol.normalise_client("Acct 001~b7~b2"), "acct 001")

    def test_identity(self):
        self.assertEqual(protocol.normalise_client("Acct 001~b12"),
                         protocol.normalise_client(" acct   001"))


class EventParseTests(unittest.TestCase):
    def test_round_trip(self):
        raw = '{"client": "Acct 001~b1", "ts": 1772140000, "kind": "login", "amount": 0.0}'
        ev = protocol.Event.parse(raw)
        self.assertEqual(ev.client, "Acct 001~b1")
        self.assertEqual(ev.ts, 1772140000)
        self.assertEqual(ev.kind, "login")
        self.assertAlmostEqual(ev.amount, 0.0)

    def test_missing_field(self):
        with self.assertRaises(ValueError):
            protocol.Event.parse('{"client": "Acct 001", "ts": 1}')

    def test_malformed_json(self):
        with self.assertRaises(ValueError):
            protocol.Event.parse("this is not json")

    def test_day_of(self):
        self.assertEqual(protocol.day_of(1772140000), "2026-02-26")


if __name__ == "__main__":
    unittest.main()
