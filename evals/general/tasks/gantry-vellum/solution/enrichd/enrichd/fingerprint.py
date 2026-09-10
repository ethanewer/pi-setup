"""Derived scalar features for an enriched event."""
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
