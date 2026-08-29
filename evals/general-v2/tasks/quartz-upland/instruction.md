# Quartz Upland — Climate-Finance Risk Engine (reproduce reference pipeline)

## Overview

You are a quantitative modelling contractor. A climate-finance risk team needs a
small, reproducible numeric engine. Three artifacts must exist by the time you
finish:

1. `/app/solve.py` — a self-contained, importable **Python 3** module containing
   four public numerical functions plus a `__main__` runner.
2. `/app/reporting_converted.py` — a **Python 3** port of the provided legacy
   Python 2 module `/app/reporting_legacy.py`.
3. `/app/answer.json` — produced by running `/app/solve.py` (see below).

Work happens in `/app`. **Do not modify** any file under `/tests` (you cannot see
it), and do not delete the fixtures already present in `/app`:
`input_data.json`, `reporting_legacy.py`, `cascade_config.ini`, `obs_daily.csv`.

Only `numpy` imports are allowed inside `solve.py`. **You must not import
`scipy` (any submodule), `scipy.integrate`, `scipy.optimize`, `scipy.stats`, or
any other third-party solver/statistics package** for the sampler. Everything
must be implemented with `numpy` (plus the standard library).

---

## Deliverable A: `/app/solve.py`

The module must be importable (a verifier does `import` of it) and must define:

- class `NonLogConvexError(Exception)`
- `softmax_attention(z, dtype) -> (weights, grad)`
- `risk_score(weights, cov) -> float`
- `wasserstein(p, q) -> float`
- `sample_density(logp, n, bounds) -> numpy.ndarray`

### A1. `softmax_attention(z, dtype)`

`z` is a 1-D list/array of real logit scores. `dtype` is one of
`"float16"`, `"float32"`, `"float64"`, or `"mixed"`.

This reproduces a temperature-bounded softmax (like an attention score) and must
remain **finite and normalized** even when `z` contains very large positive or
negative entries (overflow must be avoided by shifting before `exp`).

- Compute softmax `w_i = exp(z_i - max(z)) / sum_j exp(z_j - max(z))`.
- The returned `out` array **must have dtype exactly equal to the configured
  dtype** below, and every element must be finite.
- Return a second array `grad` = the Jacobian of the softmax
  `grad[i,j] = w_i * (delta_{ij} - w_j)`, cast to **the same dtype** as `out`,
  with all entries finite. Each row of `grad` sums to ~0 by construction.
- dtype resolution:
  - `"float16"` -> output dtype `float16`
  - `"float32"` -> output dtype `float32`
  - `"float64"` -> output dtype `float64`
  - `"mixed"`   -> the input `z` is first **cast to `float16`** and then consumed
    by an **`float32` model**: computation happens in `float32` and the output
    dtype is `float32`.

The verifier checks `sum(out) ≈ 1.0` within a per-dtype tolerance:
`float64: 1e-12`, `float32: 1e-5`, `float16: 2e-3`, `mixed: 1e-5`, and checks the
output dtype matches the table above.

**Edge cases probed by hidden tests:** extremely large positive/negative
logits (must still be finite with `sum≈1`), `"float16"` (tight-ish but not exact
sum), `"mixed"` (must really round the input to fp16 first: a signature test
detects this by feeding fp16-only-representable values).

### A2. `risk_score(weights, cov) -> float`

`weights` is a 1-D list of numbers `w`; `cov` is a square matrix `Σ`.
The covariance-weighted risk is the normalized quadratic form

```
risk = (wᵀ Σ w) / (wᵀ w)
```

Computed in `float64`. It must match a reference `float64` computation within
`rtol = 1e-9` (and `atol = 1e-12`). Raise `ValueError` on:
- `cov` not two-dimensional or not square,
- `cov` not compatible with `weights` (size mismatch),
- `weights` with zero norm.

**Probed:** several well-posed matrices, including larger magnitudes and
negative entries — exact `rtol=1e-9` agreement required.

### A3. `wasserstein(p, q) -> float`

`p` and `q` are lists of real support points of *equal cardinality n*, each
representing an empirical point of equal weight `1/n`. The 1-D Wasserstein-1
distance is

```
W(p,q) = (1/n) * sum_i | sort(p)_i - sort(q)_i |
```

where `sort(.)` sorts each list ascending. Edge contract:
- both `p` and `q` empty -> return `0.0`.
- **exactly one** of `p`/`q` empty, or the two sizes differ -> raise
  `ValueError` (malformed / unbalanced transport).
- identical multisets -> `0.0`.
- must be **symmetric**: `wasserstein(p,q) == wasserstein(q,p)` (guaranteed by
  sorting).

**Hidden test:** empty/empty, single-vs-single, identical, normal, one-empty
(must raise), and size-mismatch (must raise). Symmetry is checked by calling both
argument orders.

### A4. `sample_density(logp, count, bounds) -> numpy.ndarray`

`logp` is a Python callable `logp(x) -> float` (the log of an unnormalized
target density p`). `count` is a positive integer `n`. `bounds` is a
`(lo, hi)` tuple with `lo < hi`, both real finite. Returns `n` samples drawn
(approximately) from the target, as a `float64` array of length `n`.

**Input validation — raise on bad input:**
- `logp` not callable -> `TypeError`/`ValueError`.
- `count` not a positive integer -> `ValueError`.
- `bounds` malformed (non-finite, `lo >= hi`) -> `ValueError`.
- `logp` returns non-finite for any probed point -> `ValueError`.

**Log-concavity check (mandatory):** before sampling, the routine must perform a
runtime log-concavity test on a deterministic grid over `[lo, hi]`. Test of the
midpoint inequality: for probed points `x` and `y`, require
`logp((x+y)/2) >= (logp(x)+logp(y))/2 - 1e-7`. Test this over a grid of points
and pairs spanning the support. If any violation is found, **raise
`NonLogConvexError`** (a custom exception defined in `solve.py`) immediately —
you must NOT return samples for a non-log-concave (e.g. bimodal) target.
Sampling must then **rejection-sample** against a uniform proposal envelope over
`[lo, hi]` (recommend computing `max = max(logp)` over the grid and accepting
`x` with acceptance probability `exp(logp(x) - lmax)`).

**Hidden tests:**
- a concave (Gaussian-like) target: must return exactly `count` finite samples
  lying inside `[lo, hi]`;
- a **bimodal** target (sum of two separated Gaussians): must raise
  `NonLogConvexError`;
- `count = 0`/negative: must raise `ValueError`;
- non-callable `logp`: must raise.

### A5. `__main__` and `/app/answer.json`

When run as `python3 /app/solve.py` from `/app`, the module must
read `/app/input_data.json` and write `/app/answer.json` with exactly these
JSON keys:

- `"risk_score"`: float — `risk_score(risk_weights, risk_cov)`
- `"wasserstein"`: float — `wasserstein(dist_p, dist_q)`
- `"attention_sum"`: float — `sum(softmax(attn_z, attn_dtype)[0])`
- `"attention_dtype"`: str — the output dtype tag actually produced
  (`"float64"`, `"float32"`, `"float16"`, `"mixed"` resolves to `"float32"`)
- `"sample_mean"`, `"sample_std"`, `"sample_count"`, `"sample_within"` — mean /
  std / length / all-finite flag of `sample_density(f, sample_count,
  sample_bounds)` where the density `f` is any **unimodal log-concave**
  centered density you choose (e.g. `-0.5*((x-mu)/sig)**2`) that is concave
  over the given `sample_bounds`.

`input_data.json` fields are `risk_weights`, `risk_cov`, `dist_p`, `dist_q`,
`attn_z`, `attn_dtype`, `sample_bounds`.

The verifier runs `python3 /app/solve.py`, loads `/app/answer.json`, and
recomputes `risk_score`, `wasserstein`, and `attention_sum` / dtype
independently, requiring the same tolerances as above; it also requires
`sample_count` to equal the number you promise in `sample_count` and
`sample_within == true`.

---

## Deliverable B: `/app/reporting_converted.py`

Port `/app/reporting_legacy.py` (Python 2) into a modern **Python 3** module.
Behavior: read `/app/cascade_config.ini`, load the CSV at the configured
`csv_path`, keep only rows whose `year >= start_year`, compute the **per-year
mean of `maxtemp`**, and write the result to the configured `out_path`
(`/app/annual_summary.csv`) with header `year,mean_maxtemp` in ascending year
order. Print a short Python-3 summary line.

The port **must** use the Python 3 idioms named in the competency, and the tests
grep the source for them:
- `pathlib.Path` (do not use `os.path` string concatenation)
- `import configparser` (the lowercase Python-3 module), not `ConfigParser`
- `pandas` `read_csv(..., encoding="utf-8")` and `to_csv(..., encoding="utf-8")`
- f-strings (or other Python-3-only idioms), and no leftover Python-2 syntax
  (`xrange`, `iterkeys`, `print "..."`, `writerows` bytes mode).

The verifier runs `python3 /app/reporting_converted.py`, re-reads
`/app/annual_summary.csv` with pandas, and compares each year's mean to a
reference computed from `obs_daily.csv`.

---

## Constraints / contract summary

- Everything must run inside the container as `root`, no services, no GPU/X.
  `numpy` and `pandas` are pre-installed.
- All three deliverables must be present and executable by the time you finish.
- Never depend on reading `/tests`. The hidden cases there are mirrored new
  inputs of the exact kinds described above (additional risk matrices, extra
  distribution edge cases, other attention dtypes incl. extreme logits, and new
  concave/bimodal/invalid sampler targets).
- The scores you produce must satisfy the tolerances above; they are tight and
  the hidden cases use different numbers than the visible fixture.

Produce `/app/answer.json` so it exists as `python3 /app/solve.py` output. You
are done when all three deliverables are present and the behaviors above
hold.