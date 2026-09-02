"""kether: lightweight tide-series helpers (pure python).

This is the *working* build. It must be installed so that it imports cleanly
under the system default Python (the ``python3`` on PATH). The copy that is
present in site-packages before the repair is only a broken stub left over
from a different runtime.
"""


def flows(xs):
    """Return the algebraic sum of a numeric iterable (0.0 for empty)."""
    return float(sum(float(x) for x in xs))


def algebraic_mean(xs):
    """Arithmetic mean of a numeric iterable (0.0 for empty)."""
    acc = list(xs)
    return 0.0 if not acc else sum(float(x) for x in acc) / len(acc)


__version__ = '1.0.0'