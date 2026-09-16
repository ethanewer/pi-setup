"""Statistical summary helpers for the avocet probes."""
import math


def mean(seq):
    if not seq:
        raise ValueError("sequence is empty")
    return sum(seq) / len(seq)


def median(seq):
    if not seq:
        raise ValueError("sequence is empty")
    ordered = sorted(seq)
    n = len(ordered)
    mid = n // 2
    if n % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def pct(seq, p):
    """Nearest-rank percentile (0 < p <= 100)."""
    if not seq:
        raise ValueError("sequence is empty")
    if not (0 < p <= 100):
        raise ValueError("percentile must be in (0, 100]")
    ordered = sorted(seq)
    rank = math.ceil(p / 100.0 * len(ordered))
    return ordered[rank - 1]


def bandwidth(size_bytes, seconds):
    """Effective throughput in bytes/second."""
    if size_bytes < 0 or seconds <= 0:
        raise ValueError("invalid size or duration")
    return size_bytes / seconds


def jitter(latencies):
    """Standard deviation of a latency sample set."""
    if len(latencies) < 2:
        raise ValueError("need at least two samples")
    avg = mean(latencies)
    return math.sqrt(sum((x - avg) ** 2 for x in latencies) /
                     (len(latencies) - 1))
