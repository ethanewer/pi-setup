"""Numeric diagnostics for swellkit. The C extension ``swellkit._core`` is a
hard dependency of ``rms_amplitude``: if the package was not truly built from
source (compiled C extension missing), importing this module fails.
"""

from . import _core

__all__ = ["rms_amplitude", "mean_slice"]


def rms_amplitude(series):
    """Root-mean-square of a numeric series (may be any iterable of floats).

    An empty series yields exactly ``0.0``. The computation runs in the
    compiled C core (swellkit._core.rms).
    """
    return _core.rms([float(v) for v in series])


def mean_slice(series, start, stop):
    """Mean of ``series[start:stop]``; empty slice yields ``0.0``."""
    vals = [float(v) for v in series][start:stop]
    if not vals:
        return 0.0
    return sum(vals) / len(vals)
