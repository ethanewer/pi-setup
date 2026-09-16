"""Build statistics and reporting.

A BuildStats record is returned from ``Site.build`` and holds per-phase
timings, page/word/byte totals and any warnings collected during the build.
``report()`` renders the one-line summary the CLI prints on success.
"""

from __future__ import annotations

import time

from quaydoc.util import collapse_ws, human_bytes, now_iso


class BuildStats:
    """Tracks what a build did and how long each phase took."""

    def __init__(self):
        self.started = time.time()
        self.timings = {}
        self.page_count = 0
        self.word_count = 0
        self.bytes_written = 0
        self.warnings = []

    def phase(self, name, seconds):
        self.timings[name] = seconds

    def add_page(self, words, bytes_written):
        self.page_count += 1
        self.word_count += words
        self.bytes_written += bytes_written

    @property
    def elapsed(self):
        return time.time() - self.started

    def report(self):
        """One-line human summary (used by the CLI and the build log)."""
        total = sum(self.timings.values()) or self.elapsed
        bits = ", ".join(f"{k}={v:.2f}s" for k, v in self.timings.items())
        return (f"built {self.page_count} page(s), "
                f"{self.word_count:,} words, "
                f"{human_bytes(self.bytes_written)} in {total:.2f}s"
                + (f" ({bits})" if bits else "")
                + f" at {now_iso()}")


def estimate_reading_minutes(words, wpm=200):
    """Rough reading time in minutes rounded up (min 1)."""
    if words <= 0:
        return 1
    minutes, remainder = divmod(words, wpm)
    return minutes + (1 if remainder else 0)


def tag_histogram(pages):
    """Count pages per tag across a site, ordered by count then name."""
    counts = {}
    for page in pages:
        for tag in getattr(page, "tags", ()) or ():
            counts[tag] = counts.get(tag, 0) + 1
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))


def mean_phase_time(stats, names):
    """Average recorded phase timings for ``names`` (None when absent)."""
    values = [stats.timings[name] for name in names
              if name in stats.timings]
    if not values:
        return None
    return sum(values) / len(values)


def longest_page(pages):
    """Return the ``(word_count, page)`` pair with the most words."""
    best = None
    for page in pages:
        words = getattr(page, "word_count", 0) or 0
        if best is None or words > best[0]:
            best = (words, page)
    return best
