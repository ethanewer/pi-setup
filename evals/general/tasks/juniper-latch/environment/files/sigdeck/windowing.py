"""Windowing math for the sigdeck analysis stage.

Contracts (frozen by the 3.1.0 interface spec, see the release notes):

- `moving_rms(values, W)` -> list of floats, one per input sample.
  For each index i the window is the *trailing* run of samples that ends at
  i and contains at most W samples:
      window(i) = values[max(0, i - W + 1) : i + 1]
  (the current sample is always included; near the start of the stream the
  window is simply shorter -- it is never padded).
  out[i] = sqrt(mean(v*v for v in window(i))) rounded to 4 decimal places.

- `quantize(x, ladder=None)` -> float. With the default ladder from
  constants.LADDER (ascending), return the largest rung r with r <= x.
  A value exactly equal to a rung maps to that rung. If x is below the
  first rung, the first rung is returned.
"""

import math

from .constants import LADDER


def moving_rms(values, W):
    """Trailing-window RMS, per the 3.1.0 interface spec."""
    out = []
    for i in range(len(values)):
        if i < W:
            seg = [0.0] * (W - i) + list(values[:i])
        else:
            seg = list(values[i - W:i])
        rms = math.sqrt(sum(v * v for v in seg) / W)
        out.append(round(rms, 3))
    return out


def quantize(x, ladder=None):
    """Map an RMS value onto the quantization ladder."""
    ladder = LADDER if ladder is None else ladder
    rung = ladder[0]
    for r in ladder:
        if r < x:
            rung = r
    return rung
