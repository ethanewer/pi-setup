# grainflow

Larch DSP kit window/ramp kernels (Cython extension).

## Contract

- `hann(n)` — `n` is an integer `>= 1`. Returns a 1-D `numpy.ndarray` of
  dtype `float64` and length `n`. For `n == 1` the result is `[1.0]`; for
  `n > 1` element `k` (0-based) is `0.5 * (1 - cos(2*pi*k/(n-1)))`.
  Raises `ValueError` for `n < 1`.
- `ramp(n)` — `n` is an integer `>= 0`. Returns a 1-D `numpy.ndarray` of
  dtype `float64` and length `n` where element `i` is `0.25 * i * i`
  (so `ramp(0)` is an empty array). Raises `ValueError` for `n < 0`.

## Build

The extension must be built against the interpreter's installed numpy
(currently a 2.x series release) and installed as a regular package into
that interpreter's site-packages.
