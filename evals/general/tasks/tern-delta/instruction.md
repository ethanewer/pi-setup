# tern-delta — Delta Estuary telemetry calibration

The **Delta Estuary monitoring network** fuses telemetry from several gauges
into a single discrete distribution over gauges ("the prior"). Before the
distribution may be published it must be *calibrated*: a released distribution
`q` that stays within a forward-KL budget and a reverse-KL budget of the prior.
You author the calibration routine and produce the visible calibration.

Everything lives under `/app`. Python 3 with `numpy` is available.

## KL convention (used everywhere below)

```
KL(a || b) = sum_i a_i * log(a_i / b_i)      (natural log)
```

with the convention `0 * log(0 / b) = 0`. Both arguments are normalized to sum
to 1 before the KL is evaluated. (All provided priors are strictly positive, so
in practice no zero terms arise.)

## Deliverables (both required)

### 1. `/app/calib.py` — importable calibration module

Must be importable as `import calib` (a plain `calib.py` at `/app`). It may
import the standard library and `numpy` only. It must expose exactly this
function:

```python
def calibrate(p, r_forward, r_backward):
    ...
```

**Inputs**

- `p`: 1-D array-like (list or `numpy.ndarray`) of strictly positive numbers,
  any length >= 1. Normalize it to sum 1 before use (do not assume it is
  normalized).
- `r_forward`, `r_backward`: non-negative real numbers (the KL budgets).

**Return value** — a 1-D `numpy.ndarray` `q` such that **all** of:

1. `len(q) == len(p)`;
2. every entry is finite and **strictly positive** (`q_i > 0`);
3. `sum(q) == 1` within `1e-9`;
4. `KL(q || p) <= r_forward` and `KL(p || q) <= r_backward`.

**Guaranteed method (implement it):** build `q = (1 - alpha) * p + alpha * u`,
where `u` is the uniform distribution over the same length and
`alpha in (0, 1)`. Since `q -> p` continuously as `alpha -> 0`, any strictly
positive pair of budgets is met by driving `alpha` down: try
`alpha = 0.5, 0.25, 0.125, ...` (halving each time, at least 200 tries) and
return the **first** `q` that satisfies both budgets.

**Special case:** if `r_forward == 0` **or** `r_backward == 0`, no nonzero
`alpha` can satisfy that budget strictly through mixing — return the normalized
`p` itself immediately.

**Never** raise for valid inputs (any length >= 1, any non-negative radii, any
positive `p`); never return zeros, negatives, NaN or infinite entries.

### 2. `/app/calibrated.json` — the visible calibration

Run your routine on the shipped prior with budgets `r_forward = 0.04`,
`r_backward = 0.06`:

```python
q = calibrate(json.load(open("/app/prior.json")), 0.04, 0.06)
json.dump(list(map(float, q)), open("/app/calibrated.json", "w"))
```

`/app/calibrated.json` must be a JSON array of the resulting floats. Do **not**
modify `/app/prior.json`.

## How the verifier grades

1. It imports `/app/calib.py` and **re-runs `calibrate` on hidden priors and
   hidden budget pairs** (lengths from 1 to 12, budgets from `0` to large, one
   case so tight it needs many halvings), checking all four contract points
   above, plus the zero-budget case returning exactly the normalized prior.
2. It checks `/app/calibrated.json`: shape/values match what your own
   `calibrate` returns for the visible prior and budgets, and the two budgets
   hold.
3. It rejects modules that hard-code: hidden priors are different arrays, and
   the returned type must be a real `numpy.ndarray`.

## Constraints

- Offline, deterministic; `numpy` only (no scipy needed).
- The verifier runs with a fresh interpreter; the module must not execute the
  visible calibration on import (guard with `if __name__ == "__main__":`).
