#!/usr/bin/env python3
"""Generator for the `enrichd` service checkout.

Reproduces the whole /app/enrichd source tree (every module, the unit suite,
README, build metadata) from this single script, so the fixture is generated
rather than hand-committed. Used at image build time by tools/build_repo.sh.

Usage:
  gen_repo.py --out DIR
"""
import argparse
import os
from pathlib import Path

INIT_PY = '''"""enrichd - resilient streaming event-enrichment service."""

__version__ = "2.4.1"
'''

MAIN_PY = '''"""``python3 -m enrichd`` entry point."""
import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main())
'''

PROTOCOL_PY = '''"""Wire protocol: JSON-lines events in, enriched JSON-lines events out.

Input events arrive one JSON object per line.  Clients reach the service from
many collectors, so the ``client`` field may carry arbitrary casing, padding,
and an optional collector tag suffix (for example ``"Acct 001~b7"``); the
canonical spelling is defined in :func:`normalise_client`.  The service emits
exactly one enriched object per input event, in input order, containing every
original field plus the enrichment fields produced by the engine.
"""
import json
import re
import time
from dataclasses import dataclass

REQUIRED_FIELDS = ("client", "ts", "kind")

# Enrichment fields the engine attaches to every output event.
ENRICHED_FIELDS = (
    "client_key",
    "day",
    "segment",
    "digest_mean",
    "digest_energy",
    "digest_l1",
)

_TAG_RE = re.compile(r"~[0-9a-z]+")


class ProtocolError(ValueError):
    """Raised when an input line is not a well-formed event."""


def normalise_client(raw):
    """Canonical spelling of a client identifier.

    Client identifiers arrive from many collectors that case differently,
    pad or repeat whitespace, and append a collector tag ("Acct 001~b7", the
    batch watermark of the hop that forwarded the event).  None of that is
    part of the client's identity.  The canonical spelling - lowercase, runs
    of whitespace collapsed to a single space, collector tags stripped - is
    the one carried in the emitted ``client_key`` field and the one used
    wherever the service groups or keys by identity.
    """
    s = " ".join(_TAG_RE.sub("", raw.lower()).split())
    return s


def day_of(ts):
    """UTC calendar date for an epoch timestamp, ISO-8601 (YYYY-MM-DD)."""
    return time.strftime("%Y-%m-%d", time.gmtime(ts))


@dataclass
class Event:
    client: str
    ts: int
    kind: str
    amount: float
    orig: dict

    @classmethod
    def parse(cls, raw):
        """Parse one JSON-lines event from its raw text."""
        obj = json.loads(raw)  # JSONDecodeError -> ValueError
        if not isinstance(obj, dict):
            raise ProtocolError("event is not a JSON object")
        for k in REQUIRED_FIELDS:
            if k not in obj:
                raise ProtocolError("missing required field %r" % k)
        client = obj["client"]
        if not isinstance(client, str) or not client.strip():
            raise ProtocolError("client must be a non-blank string")
        ts = obj["ts"]
        if not isinstance(ts, int):
            raise ProtocolError("ts must be an integer")
        kind = obj["kind"]
        if not isinstance(kind, str):
            raise ProtocolError("kind must be a string")
        amount = obj.get("amount", 0.0)
        if not isinstance(amount, (int, float)):
            raise ProtocolError("amount must be numeric")
        return cls(client=client, ts=ts, kind=kind,
                   amount=float(amount), orig=obj)
'''

EMBED_PY = '''"""Deterministic per-client feature material.

The service scores every event against a fixed-length feature vector derived
deterministically from the client's canonical identifier, so the same client
always yields the same material on any host and no external data files are
required.
"""
import functools
import hashlib
import math

EMBED_DIM = 256
DIGEST_LEN = 2048
SEGMENT_COUNT = 6


def _mix(seed):
    """Deterministic pseudo-random floats in [-1, 1] for a small integer seed."""
    state = int.from_bytes(
        hashlib.sha256(("enrichd.mix:%d" % seed).encode("ascii")).digest(),
        "big",
    )
    out = []
    for _ in range(EMBED_DIM):
        state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        out.append(((state >> 11) * (1.0 / (1 << 53))) * 2.0 - 1.0)
    return out


@functools.lru_cache(maxsize=256)
def embedding(client_key):
    """Feature vector for a canonical client key (a tuple of floats)."""
    seed = int(hashlib.sha256(client_key.encode("utf-8")).hexdigest()[:16], 16)
    return tuple(_mix(seed))


def day_ordinal(day):
    """Small integer derived from a YYYY-MM-DD date, used by the fold."""
    return int(day[-2:]) % 28


def build_digest(client_key, day):
    """The daily behaviour digest: a fixed-length deterministic feature fold.

    This is the expensive fold the profile cache exists to memoise: it walks
    the client embedding several times and mixes in calendar-derived weights,
    so per-event recomputation is wasteful when events arrive in bursts.
    Values are pure functions of (client_key, day).
    """
    emb = embedding(client_key)
    d = day_ordinal(day)
    out = [0.0] * DIGEST_LEN
    for i in range(DIGEST_LEN):
        src = (i * 7 + d) % EMBED_DIM
        w = 0.5 + 0.5 * math.sin((i + d + 1) * 0.61803398875)
        out[i] = emb[src] * (2.0 * w) + emb[(src + 13) % EMBED_DIM] * 0.25
    return out
'''

FINGERPRINT_PY = '''"""Derived scalar features for an enriched event."""
import math


def digest_scalars(digest):
    """Reduce a daily behaviour digest to the four published scalars.

    Returned values are stable to far beyond the six decimal places required
    by the wire contract.
    """
    n = len(digest)
    total = 0.0
    energy = 0.0
    l1 = 0.0
    for v in digest:
        total += v
        energy += v * v
        l1 += abs(v)
    mean = total / n
    segment = int((mean + 2.0) * 12.5) % 6
    return mean, math.sqrt(energy / n), l1 / n, segment
'''

CACHE_LEAKY_PY = '''"""Profile cache.

The enrichment engine consults this cache for a client's daily behaviour
digest before computing it, so repeated events avoid the costly digest fold.
Digests are pure functions of the normalised client identifier and the day,
so the cache is a strict memoisation: it can be sized, evicted or dropped
without changing a single output byte.
"""
from .embed import build_digest
from . import protocol

normalise_client = protocol.normalise_client


class ProfileCache:
    """Memoisation of daily behaviour digests.

    One entry per (client, day) pair seen on the wire.  A cache hit is a
    plain dict lookup; a miss computes the digest (a pure function) and
    stores it.  Hits and misses are counted for observability.
    """

    def __init__(self, max_entries=None):
        self._digests = {}
        self._order = []
        self.max_entries = max_entries
        self.hits = 0
        self.misses = 0

    def __len__(self):
        return len(self._digests)

    def fetch(self, client, day):
        """Return the digest for (client, day), building and storing it if absent.

        The digest itself is always computed from the canonical (normalised)
        client and the day; this method memoises it keyed by the wire form of
        the pair.
        """
        key = (client, day)
        digest = self._digests.get(key)
        if digest is None:
            self.misses += 1
            digest = build_digest(normalise_client(client), day)
            if self.max_entries is not None and len(self._digests) >= self.max_entries:
                self._evict_one()
            self._digests[key] = digest
            self._order.append(key)
        else:
            self.hits += 1
        return digest

    def _evict_one(self):
        """Drop the oldest entry (FIFO).  Safe: entries are pure functions."""
        if self._order:
            oldest = self._order.pop(0)
            self._digests.pop(oldest, None)
'''

OUTPUT_PY = '''"""Append-only line-serialised output sink."""
import json
import os


class OutputSink:
    """Writes one JSON object per line to a file, flushing periodically."""

    def __init__(self, path, flush_every=8):
        self.path = path
        self.flush_every = max(1, flush_every)
        self.fh = None
        self.written = 0

    def __enter__(self):
        parent = os.path.dirname(self.path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        self.fh = open(self.path, "w", encoding="utf-8", buffering=1)
        return self

    def write(self, obj):
        self.fh.write(json.dumps(obj, separators=(",", ":")) + "\\n")
        self.written += 1
        if self.written % self.flush_every == 0:
            self.fh.flush()

    def __exit__(self, exc_type, exc, tb):
        if self.fh is not None:
            self.fh.flush()
            self.fh.close()
        return False
'''

STATS_PY = '''"""Lightweight runtime counters, reported to stderr at shutdown."""
import sys
import time


class Stats:
    """Per-run counters the engine updates; report() prints them to stderr."""

    def __init__(self):
        self.started = time.time()
        self.processed = 0
        self.malformed = 0

    def report(self, cache_hits, cache_misses, cache_len):
        elapsed = time.time() - self.started
        sys.stderr.write(
            "enrichd: processed=%d malformed=%d cache_hits=%d cache_misses=%d "
            "cache_len=%d elapsed=%.1fs\\n"
            % (self.processed, self.malformed, cache_hits, cache_misses,
               cache_len, elapsed)
        )
'''

ENGINE_PY = '''"""Streaming enrichment engine.

The engine reads one event per line from the input stream, enriches it as
documented in the README, and writes one line per event to the output sink.
The service is built to stay up for long uninterrupted runs: the input loop
is allocation-light, the profile cache bounds its own history, and the
pipeline drains and flushes cleanly when the stream closes or on
SIGTERM/SIGINT.
"""
import signal
import sys

from . import fingerprint, protocol
from .cache import ProfileCache
from .output import OutputSink
from .stats import Stats


class _Shutdown(Exception):
    """Raised inside the input loop when a termination signal arrives."""


def _term_handler(signum, frame):
    raise _Shutdown()


def _r6(x):
    return round(x, 6)


def enrich_event(ev, digest):
    """Attach the published enrichment fields to an event's original fields."""
    mean, energy, l1n, segment = fingerprint.digest_scalars(digest)
    out = dict(ev.orig)
    out["client_key"] = protocol.normalise_client(ev.client)
    out["day"] = protocol.day_of(ev.ts)
    out["segment"] = segment
    out["digest_mean"] = _r6(mean)
    out["digest_energy"] = _r6(energy)
    out["digest_l1"] = _r6(l1n)
    return out


def run(args):
    """Process stream(args.input) into args.output; returns the exit code."""
    cache = ProfileCache(max_entries=args.max_profiles)
    stats = Stats()
    signal.signal(signal.SIGTERM, _term_handler)
    signal.signal(signal.SIGINT, _term_handler)
    try:
        with OutputSink(args.output, flush_every=max(1, args.flush_every)) as sink:
            if args.input == "-":
                stream = sys.stdin
            else:
                stream = open(args.input, "r", encoding="utf-8")
            try:
                for raw in stream:
                    line = raw.strip()
                    if not line:
                        continue
                    try:
                        ev = protocol.Event.parse(line)
                    except ValueError:
                        stats.malformed += 1
                        continue
                    day = protocol.day_of(ev.ts)
                    digest = cache.fetch(ev.client, day)
                    sink.write(enrich_event(ev, digest))
                    stats.processed += 1
            finally:
                if args.input != "-":
                    stream.close()
    except _Shutdown:
        pass
    stats.report(cache.hits, cache.misses, len(cache))
    return 0
'''

CLI_PY = '''"""Command line interface."""
import argparse
import sys

from . import __version__, engine


def build_parser():
    parser = argparse.ArgumentParser(
        prog="enrichd",
        description="Streaming event-enrichment service.  Reads JSON-lines "
                    "events from the input stream, writes one enriched "
                    "object per event to --output, and keeps going until "
                    "the stream closes.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("process", help="process an event stream")
    run.add_argument("--input", default="-",
                     help="input event stream; '-' reads stdin (default)")
    run.add_argument("--output", required=True,
                     help="path of the enriched .jsonl output")
    run.add_argument("--flush-every", type=int, default=8,
                     help="flush the output sink every N events")
    run.add_argument("--max-profiles", type=int, default=None,
                     help="cap the profile cache at N entries (default: unbounded)")

    ver = sub.add_parser("version", help="print the version and exit")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.command == "version":
        print(__version__)
        return 0
    if args.flush_every < 1:
        print("enrichd: --flush-every must be >= 1", file=sys.stderr)
        return 2
    return engine.run(args)
'''

TESTS_INIT_PY = ""  # package marker for unittest discovery

TEST_PROTOCOL_PY = '''import sys
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
'''

TEST_CACHE_PY = '''import sys
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
'''

TEST_ENGINE_PY = '''import json
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
                input="\\n".join(json.dumps(e) for e in events) + "\\n",
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
                input="\\n".join(lines) + "\\n",
                cwd=str(_ROOT), capture_output=True, text=True, timeout=120)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr[-800:])
            got = [l for l in out.read_text().splitlines() if l.strip()]
            self.assertEqual(len(got), len(events))


if __name__ == "__main__":
    unittest.main()
'''

README_MD = '''# enrichd

`enrichd` is a streaming event-enrichment service.  Collectors across the
edge mesh push JSON-lines telemetry events into it over a pipe; enrichd
enriches every event with derived features of the client's recent behaviour
and a few pageview/purchase scalars, and writes one enriched object per
event to its output path.  It is deployed as a long-running process under a
supervisor that restarts it on crash and re-feeds the tail of the input on
restart, so steady-state memory behaviour matters as much as throughput.

Pure standard library.  No network access is required: all feature material
is derived deterministically from the client identifier.

## Layout

    enrichd/            service package
      cli.py            argument parsing and dispatch
      engine.py         the streaming input loop
      protocol.py       event schema, canonical client spelling, day math
      embed.py          deterministic feature material and digest fold
      fingerprint.py    digest -> published scalars
      cache.py          profile cache (daily behaviour digests)
      output.py         line-serialised output sink
      stats.py          runtime counters reported on stderr
    tests/              unit suite (python3 -m unittest discover -s tests -t .)
    workloads/          load fixtures

## Run

    echo '{"client": "Acct 001~b1", "ts": 1772140000, "kind": "login", "amount": 0.0}' \\
      | python3 -m enrichd process --output out.jsonl

    python3 -m enrichd process --input workloads/visible.jsonl --output out.jsonl

The process reads one event per line from the input stream, enriches it, and
keeps going until the stream closes (or SIGTERM/SIGINT arrives), then drains,
flushes and exits 0.  Output is one JSON object per input event, in input
order, with the original fields plus the enrichment fields listed below.

## Enrichment contract

Per event with fields `client`, `ts` (epoch seconds), `kind`, optional
`amount`:

| Field          | Meaning                                                          |
|----------------|------------------------------------------------------------------|
| `client_key`   | canonical spelling of `client` (lowercase, collapsed whitespace, collector tag stripped) |
| `day`          | UTC calendar date of `ts`, ISO-8601 (`YYYY-MM-DD`)               |
| `segment`      | behaviour segment, integer 0..5                                  |
| `digest_mean`  | mean of the 2048-value daily behaviour digest, float             |
| `digest_energy`| sqrt(mean of squared digest values), float                       |
| `digest_l1`    | mean absolute digest value, float                                |

Floats are rounded to 6 decimal places.

## Development

    make test       # run the unit suite
    make smoke      # unit suite + a small run over workloads/visible.jsonl

The unit suite must stay green; nothing in it depends on wall clock or
network.
'''

MAKEFILE = '''PY ?= python3

.PHONY: test smoke

test:
	$(PY) -m unittest discover -s tests -t . -q

smoke: test
	$(PY) -m enrichd process --input workloads/visible.jsonl --output /tmp/enrichd.smoke.jsonl
	wc -l workloads/visible.jsonl /tmp/enrichd.smoke.jsonl
	rm -f /tmp/enrichd.smoke.jsonl
'''

PYPROJECT_TOML = '''[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "enrichd"
version = "2.4.1"
description = "Resilient streaming event-enrichment service"
requires-python = ">=3.10"

[tool.setuptools]
packages = ["enrichd"]
'''

GITIGNORE = '''__pycache__/
*.pyc
*.pyo
.venv/
.mypy_cache/
'''


FILES = {
    "enrichd/__init__.py": INIT_PY,
    "enrichd/__main__.py": MAIN_PY,
    "enrichd/protocol.py": PROTOCOL_PY,
    "enrichd/embed.py": EMBED_PY,
    "enrichd/fingerprint.py": FINGERPRINT_PY,
    "enrichd/cache.py": None,  # supplied from CACHE_LEAKY_PY below
    "enrichd/output.py": OUTPUT_PY,
    "enrichd/stats.py": STATS_PY,
    "enrichd/engine.py": ENGINE_PY,
    "enrichd/cli.py": CLI_PY,
    "tests/__init__.py": TESTS_INIT_PY,
    "tests/test_protocol.py": TEST_PROTOCOL_PY,
    "tests/test_cache.py": TEST_CACHE_PY,
    "tests/test_engine.py": TEST_ENGINE_PY,
    "workloads/.gitkeep": "",
    "README.md": README_MD,
    "Makefile": MAKEFILE,
    "pyproject.toml": PYPROJECT_TOML,
    ".gitignore": GITIGNORE,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for rel, body in FILES.items():
        target = out / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if body is None:
            body = CACHE_LEAKY_PY
        target.write_text(body, encoding="utf-8")
        print("wrote %s" % target)


if __name__ == "__main__":
    main()
