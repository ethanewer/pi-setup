# Cedar Jetty — signal & calibration kernels

The research buoy `Cedar Jetty` ships a small numerical-calibration toolkit. You must
author that toolkit as a single Python module and run one analysis against a fixed input signal.

You will produce **two deliverables**:

1. `/app/kernels.py` — an importable Python module exposing five functions (defined below), plus
   a small clock helper.
2. `/app/out.npy` — the numpy binary fixed by the "visible" analysis described below.

Everything is pure numeric work on numpy / scipy / sympy. Be exact: the verifier re-computes every
number independently and requires close (or exact) agreement.

---

## 1. The kernel module `/app/kernels.py`

The module must be importable as `import kernels` from directory `/app` (a plain `kernels.py`
at that path). It may import the standard library, `numpy`, `sympy`, and `scipy.signal`. It must
**not** import any numeric-integration or optimization stack — in particular it must never
`import scipy.integrate`, `from scipy import integrate` / `odeint` / `solve_ivp`,
`import scipy.optimize`, or `from scipy.optimize import ...`. The verifier scans the source text
for these forbidden tokens and fails if any appears. (Use `scipy.signal` and `scipy.signal.stft`
freely — they are allowed.)

### 1.a `hand_kin(c, y0, t_beg, t_end, step) -> float`

Hand-written 4th-order Runge–Kutta forward integration of

```
dy/dt = -c * y,   y(t_beg) = y0
```

from `t_beg` to `t_end`, with no numeric-integration library. It computes the number of
substeps `n = ceil((t_end - t_beg) / step)` (at least 1), uses a uniform substep
`h = (t_end - t_beg) / n`, and does classic RK4 (k1..k4 then `y += h/6*(k1+2k2+2k3+k4)`).

**Returns** the final `y(t_end)` as a `float`.

All arguments are real numbers; `step > 0`, `c >= 0`, `t_end >= t_beg`. The verifier compares the
returned value to the analytic solution `y(t_end) = y0 * exp(-c*(t_end-t_beg))` to within a
relative tolerance of `1e-4`. (Write it, don't just paste the exponential.)

### 1.b `smoothed_distribution(p, r_forward, r_backward) -> numpy.ndarray`

Produce a probability array over a fixed vocabulary that satisfies both a **forward-KL** and a
**reverse-KL** constraint relative to a provided strictly-positive distribution `p`.

KL everywhere is defined as `KL(a||b) = sum_i a_i * log(a_i / b_i)` with the convention
`0*log(0/b) = 0`. Both `a` and `b` are normalized to sum to 1 before the KL is taken.

Contract:

- `p` is a 1-D array of strictly positive numbers (each `p_i > 0`). Normalize it to sum 1
  before use.
- `r_forward` and `r_backward` are non-negative real numbers (radii).
- Return a 1-D `numpy.ndarray` `q` of the **same length** as `p`, where every entry
  `q_i > 0`, `sum(q) == 1` (within `1e-9`), and all entries are finite, such that
  `KL(q || p) <= r_forward` and `KL(p || q) <= r_backward`.

**Guaranteed method (use it or any equivalent):** build `q = normalize((1-alpha)*p + alpha*u)`
where `u` is the uniform distribution over the vocabulary and `alpha in (0,1)` is adapted.
Because `q -> p` as `alpha -> 0`, any strictly-positive choice of radii can be met by driving the
alpha down. Repeatedly try `alpha = 0.5, 0.25, 0.125, ...` (halving) and check whether the two
KLs already satisfy the radii, returning the first distribution that does.

- If **either** radius is exactly `0`, no nonzero `alpha` works correctly because in that case
  both radii can only be satisfied by `q == p` exactly. Return the normalized `p` itself.

Edge behaviour the verifier will probe: length-1 distributions, `r_forward == r_backward == 0`,
a `r` so small it needs many halvings, and distributions whose shape the caller always preserves.

### 1.c `stft_mag(signal, fs, nperseg, noverlap, nfft) -> numpy.ndarray`

Compute a short-time Fourier transform with **scipy** at exactly fixed parameters and return the
**linear** magnitude spectrogram (never decibels).

Call exactly:

```python
_ , _ , z = scipy.signal.stft(
    signal, fs=fs, window="hann", nperseg=nperseg, noverlap=noverlap,
    nfft=nfft, detrend=False, return_onesided=True,
    boundary="zeros", padded=True,
)
return numpy.abs(z)
```

- `signal`: 1-D float array or list.
- `fs` positive float; `nperseg` positive int; `0 <= noverlap < nperseg`; `nfft >= nperseg`.
- Return `numpy.abs(z)`, a 2-D float ndarray of shape `(nfreq, ntime)`. The values are non-negative
  linear magnitudes.

The verifier recompute the identical scipy call on the same samples and compares elementwise
`allclose(rtol=1e-9, atol=1e-12)`, and further asserts the values are linear (matches the 
magnitude reference — not in decibels).

### 1.d `round_accuracy(model, truth, tol=5e-3) -> list`

For a set of competition rounds, compare matching question ids by exact numeric match, ignore
every pair where either side is invalid, and report per-round correct / total / accuracy.

- `model` and `truth` are JSON-compatible dicts mapping **round id** (int or str) to a dict of
  `question id -> value`. A `value` is either **a real number** or the string `"ERR"` (an error /
  invalid marker). Question ids can be int or str.
- For each round that appears in **either** dict:
  - A question id is a **candidate pair** if it appears in **both** `model[r]` and `truth[r]`.
    Ids present on only one side are **unmatched and ignored** entirely (not counted anywhere).
  - A candidate pair is **invalid** (dropped) if either side's value is `"ERR"` (or any
    non-numeric value). Dropped pairs do not count toward `correct` or `total`.
  - A surviving pair counts toward `total`; it is `correct` when `|model_value - truth_value| < tol`
    (strictly less than `tol`, a plain map value compare, no rounding of inputs).
  - `accuracy = correct / total` rounded **half-up** to 3 decimal places (a proportion in
    `[0,1]`); if `total == 0`, the round's accuracy is `None` (JSON null).
- Return a `list` of dicts, sorted by round id, one per round present, of the shape
  `{"round": <round id>, "correct": int, "total": int, "accuracy": float | None}`.

Half-up kicks ties away from zero: `round_half_up(x, 3) = floor(x * 1000 + 0.5) / 1000` (clamped
to `[0,1]`). The verifier recomputes every number itself from the raw inputs and compares
exactly (int equality for `correct`/`total`, `3-decimals`-after-half-up equality for `accuracy`,
`None` when `total == 0`).

**Edge cases probed by hidden rounds**: rounds with no candidate pairs at all (accuracy `None`),
single valid pair, `"ERR"` on either side only, ids on only one side, half-up ties (e.g. `2/3`
`=> 0.667`, `1/8 => 0.125`), duplicate / repeated ids, and rounds whose ids are strings.

### 1.e `symbolic_integral(degree) -> dict`

Express an integrand and definite-integral interval as **symbolic sympy objects** so it can be
integrated exactly rather than numerically.

- `degree` is an integer in `0..12`.
- Return a `dict` with exactly four sympy objects:

```
{
  "variable": sp.Symbol("x"),
  "integrand": sp.Symbol("x") ** degree,
  "lower": sp.Integer(0),
  "upper": sp.Integer(1),
}
```

The verifier calls `sympy.integrate(integrand, (x, lower, upper))` on your returned objects and
asserts the symbolic result **equals** `sympy.Rational(1, degree + 1)` **exactly** (no numeric
decimal). It also asserts `x` is a `sympy.Symbol`, the interval endpoints are `sympy.Integer`s,
and that `sympy.integrate` accepts them. For `degree == 1` the integrand must come out exactly
`x**1` under `sympy` — not `x**1` numerically, not a float.

---

## 2. Fixed visible analysis → `/app/out.npy`

The verifier also needs the toolkit's headline artefact: the linear STFT magnitude spectrogram of
a known two-tone burst. Do **not** hand-write this array — compute it by **running** `stft_mag`.

Fixed recipe (reproducible, deterministic):

```
fs  = 2048.0
L   = 2048
t   = numpy.arange(L) / fs                       # 0.0 .. (2047/2048) s
signal = 3.0*sin(2*pi*220*t) + 1.5*sin(2*pi*880*t)

out = kernels.stft_mag(signal, fs=2048.0, nperseg=256, noverlap=192, nfft=512)
numpy.save("/app/out.npy", out)
```

`/app/out.npy` must therefore be a 2-D `float64` ndarray computed by `stft_mag` from that exact
signal, with `nperseg=256`, `noverlap=192`, `nfft=512`, `fs=2048.0`.

The verifier loads `/app/out.npy`, rebuilds the same signal locally, recomputes the reference
magnitude array with the identical scipy call, and asserts shape equality plus
`allclose(rtol=1e-9, atol=1e-12)`. It also requires the array to be real 2-D with non-negative
finite entries.

---

## 3. What must NOT be done

- Do not modify files outside `/app`. Do not create `response`-running side-effects that fake
  results. There is **no** hidden data on the image; every input is JSON re-fed by the grader
  into your functions.
- Do not write `/app/out.npy` by copying a precomputed blob — compute it with `stft_mag`.
- The module must be `import kernels`-able from `/app` with `numpy`, `scipy`, `sympy` present.

You may place private helpers in `/app/kernels.py` as long as the five named functions and the
module import behave exactly as specified.