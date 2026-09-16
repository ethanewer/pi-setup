"""Performance regression test for sundial's hot path.

The hot operation must scale near-linearly: doubling the input size twice
(16000 -> 32000 -> 64000) should about quadruple the runtime (ratio ~4), not
sixteen-fold it (ratio ~16 for a quadratic hot path).  The size span is wide
so the ratio is stable across hosts of very different speeds; an absolute
bound backs up the ratio on heavily loaded hosts where both timings grow a
common noise floor.  Timings use the minimum of several runs so background
load on the host does not inflate a measurement.
"""

import gc
import random
import time

from sundial.window import slide


def _min_runtime(n, k, repeats=5):
    """Smallest wall time (seconds) over ``repeats`` runs at size n."""
    rng = random.Random(20250106 + n)
    data = [rng.randrange(0, 1 << 20) for _ in range(n)]
    gc.collect()
    gc.disable()
    try:
        best = None
        for _ in range(repeats):
            t0 = time.perf_counter()
            slide(data, k)
            elapsed = time.perf_counter() - t0
            if best is None or elapsed < best:
                best = elapsed
    finally:
        gc.enable()
    return best


def test_sliding_window_scales_near_linearly():
    t_small = _min_runtime(16000, 8000)
    t_large = _min_runtime(64000, 32000)
    growth = t_large / t_small
    assert t_large <= 2.5, (
        "hot path too slow at n=64000 (%.3fs); a linear implementation "
        "completes in tens of milliseconds" % t_large
    )
    assert growth <= 6.0, (
        "runtime grows %.2fx over two doublings of the input; a linear "
        "implementation stays near 4x, a quadratic one reaches ~16x" % growth
    )