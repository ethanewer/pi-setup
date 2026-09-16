import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))

from enrichd import protocol
from enrichd.cache import ProfileCache
from enrichd.engine import enrich_event

SPELLINGS = (
    "Acct 001",
    "acct 001 ",
    " ACCT 001",
    "acct   001",
)


def make_events(n_clients=4, rounds=3):
    rows = []
    ts = 1772140000
    for r in range(rounds):
        for c in range(n_clients):
            base = "Acct %03d" % c
            rows.append({
                "client": "%s~b%d" % (SPELLINGS[r % len(SPELLINGS)].replace("001", "%03d" % c), r),
                "ts": ts,
                "kind": "pageview",
                "amount": float(c),
            })
            ts += 120
    return rows


class EngineTests(unittest.TestCase):
    def test_end_to_end_stdin(self):
        events = make_events()
        cache = ProfileCache()
        expected = []
        for obj in events:
            ev = protocol.Event.parse(json.dumps(obj))
            day = protocol.day_of(ev.ts)
            digest = cache.fetch(ev.client, day)
            expected.append(enrich_event(ev, digest))

        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "out.jsonl"
            proc = subprocess.run(
                [sys.executable, "-m", "enrichd", "process",
                 "--output", str(out), "--flush-every", "2"],
                input="\n".join(json.dumps(e) for e in events) + "\n",
                cwd=str(_ROOT), capture_output=True, text=True, timeout=120)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr[-800:])
            got = [json.loads(line) for line in out.read_text().splitlines()]
            self.assertEqual(len(got), len(expected))
            for g, e in zip(got, expected):
                self.assertEqual(sorted(g), sorted(e))
                for k, v in e.items():
                    if isinstance(v, float):
                        self.assertAlmostEqual(g[k], v, places=6)
                    else:
                        self.assertEqual(g[k], v)

    def test_skips_malformed_lines(self):
        events = make_events(n_clients=2, rounds=2)
        lines = [json.dumps(e) for e in events]
        lines.insert(2, "not-json-at-all")
        lines.insert(5, '{"client": 7, "ts": 1, "kind": "x"}')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "out.jsonl"
            proc = subprocess.run(
                [sys.executable, "-m", "enrichd", "process", "--output", str(out)],
                input="\n".join(lines) + "\n",
                cwd=str(_ROOT), capture_output=True, text=True, timeout=120)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr[-800:])
            got = [l for l in out.read_text().splitlines() if l.strip()]
            self.assertEqual(len(got), len(events))


if __name__ == "__main__":
    unittest.main()
