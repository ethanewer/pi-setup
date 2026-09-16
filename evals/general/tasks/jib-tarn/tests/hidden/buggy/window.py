"""Windowed operations over event series.

The public entry point is :func:`slide`, which computes the maximum of every
contiguous window of a fixed size.
"""

from typing import List, Sequence

__all__ = ["slide"]


def slide(data: Sequence[int], size: int) -> List[int]:
    """Return the maximum of every contiguous window of ``size`` values.

    ``data`` holds non-negative integers (event magnitudes); ``size`` must be
    at least 1 (smaller values are clamped to 1).  Windows are scanned left to
    right: for a series of length *n* the result has ``n - size + 1`` entries.
    When ``size`` exceeds the series length (or the series is empty) the
    result is empty.
    """
    k = max(1, size)
    n = len(data)
    if n == 0 or k > n:
        return []
    out = []
    for i in range(n - k + 1):
        out.append(max(data[i : i + k]))
    return out
