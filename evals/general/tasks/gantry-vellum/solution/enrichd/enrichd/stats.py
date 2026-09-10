"""Lightweight runtime counters, reported to stderr at shutdown."""
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
            "cache_len=%d elapsed=%.1fs\n"
            % (self.processed, self.malformed, cache_hits, cache_misses,
               cache_len, elapsed)
        )
