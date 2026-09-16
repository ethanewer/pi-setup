"""Streaming enrichment engine.

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
