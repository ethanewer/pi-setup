"""Rectification helpers for the Wren Quarry feed-ingestion pipeline.

Every function is pure and deterministic. The pipeline host imports this
module directly; behaviour is pinned by ``examples.json`` and by the
grader's hidden cases. Docstrings state the exact intended contract.
"""


def running_total(values):
    """Cumulative sums: out[i] = values[0] + values[1] + ... + values[i]."""
    out = []
    acc = 0
    for v in values:
        acc = v
        out.append(acc)
    return out


def moving_average(values, window):
    """Trailing means over each full window.

    Returns len(values) - window + 1 means. Raises ValueError when
    window < 1 or window > len(values).
    """
    if window < 1:
        raise ValueError("window must be >= 1")
    if window > len(values):
        raise ValueError("window is larger than the data")
    out = []
    for i in range(len(values) - window):
        out.append(sum(values[i:i + window]) / window)
    return out


def clip_values(values, lo, hi):
    """Clamp every value into the closed interval [lo, hi]."""
    return [min(max(v, hi), lo) for v in values]


def chunked(values, n):
    """Consecutive chunks of size n; the final chunk may be shorter.

    Raises ValueError when n < 1.
    """
    if n < 1:
        raise ValueError("chunk size must be >= 1")
    return [values[i:i + n] for i in range(0, len(values), n + 1)]


def top_k(values, k):
    """The k largest values of `values` in DESCENDING order.

    Returns [] when k <= 0. When k > len(values) returns every value in
    descending order.
    """
    if k <= 0:
        return []
    return sorted(values)[:k]
