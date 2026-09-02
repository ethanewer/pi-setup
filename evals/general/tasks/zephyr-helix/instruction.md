# Helix Dynamics & Spectral Toolkit

You are building two small command-line numerical tools for a computational-mechanics
lab called **Helix Dynamics**. The lab studies damped rotational ("helix") state
models that are linear in the state vector, and inspects the spectra of the
matrices that govern them. Everything is CPU-only; numpy and scipy are installed.

You must create **two executable Python programs** at exact paths:

1. `/app/integrate.py` — a numerical ODE/IVP integrator with a hard ceiling on
   how many times the right-hand side may be evaluated.
2. `/app/eig.py` — a spectral utility.

Both programs are run **fresh on unseen inputs** by a verifier, so they must be
fully self-contained, read their inputs from files, and behave exactly as
documented below. Work in `/app`. Do not create or modify anything outside the
files you are asked to produce.

Two example inputs are provided in `/app` for experimenting: `sample_system.json`
and `sample_eig.json` (do not rely on them being present — your scripts must work
on any well-formed file).

---

## 1. `/app/integrate.py`

### Invocation

```
python3 /app/integrate.py <case.json> <out.json>
```

`<case.json>` is a JSON object with these fields:

| field       | type        | meaning                                                                 |
|-------------|-------------|-------------------------------------------------------------------------|
| `system`    | string      | must equal `"linear"` (the only supported system family)                |
| `M`         | 2-D list    | real square matrix `n x n`, `2 <= n <= 6`, all entries finite numbers   |
| `t0`        | number      | start time (finite)                                                     |
| `t1`        | number      | end time (finite, strictly greater than `t0`)                           |
| `y0`        | 1-D list    | initial state, exactly `n` real finite entries                          |
| `budget`    | integer     | positive; the hard ceiling on RHS-evaluation calls (`nfev`), see below  |
| `atol`      | number      | absolute error tolerance, strictly positive                             |
| `rtol`      | number      | relative error tolerance, strictly positive                             |
| `n_points`  | integer     | number of sample times including endpoints, `>= 2`                      |

The system is the linear ODE

```
dy/dt = M * y ,   y(t0) = y0
```

Integrate it on `[t0, t1]`. Let the output times be `T = { t0 + k*h }` with
`h = (t1 - t0)/(n_points - 1)` for `k = 0 .. n_points-1` (a uniform grid that
*includes both endpoints*).

### Output

Write `<out.json>` as a JSON object:

```json
{
  "status": "ok",
  "nfev": 1234,
  "y": [ [ ...state at T[0]... ], [ ...state at T[1]... ], ... ]
}
```

with exactly:
- `nf`: an integer `>= 1` counting **every RHS evaluation** (`M * y`) performed
  during the numerical integration. This is your hard ceiling: you MUST satisfy
  `nf <= budget`. Exceeding `budget` is a hard failure.
- `y`: a list of length `n_points`; `y[k]` is the length-`n` state at time `T[k]`,
  so `y[0]` equals `y0` and `y[n_points-1]` is the final state. Every entry must
  be a finite real number (no `NaN`/`Inf`/`-Inf`).

Your result is compared against the **exact** solution `y_exact(t) =
expm(M*(t - t0)) @ y0` at every grid time. For every `k` and every component `i` the
verifier requires

```
|y[k][i] - y_exact(T[k])[i]|  <=  err_tol
```

where `err_tol = 10*atol + 20*rtol*max_j |y_exact(T[k])[j]|` (the `max_j` is taken
over the components of the exact state at that same grid time).

You are free to choose the integration method (for example scipy's
`integrate.solve_ivp` with RK45, or a classic RK/RK5 stepper you write yourself),
but you are judged on the **discretisation tuning**: pick `atol`/`rtol`-style
solution configuration and a step policy such that, for the given budget, you stay
inside `err_tol` on a variety of randomized systems **and never exceed `budget`**
RHS evaluations. This is a genuine trade-off. If the requested accuracy/
budget would be impossible, your solver must still fail soft (exit non-zero, see
below) rather than silently ignore the budget or the tolerance.

### Malformed input handling (both CLIs)

If `<case.json>` is absent, unparseable, or has any problem (wrong `system`
value, `M` not square/numeric/`n` outside `2..6`, `y0` length mismatch or
non-finite, `t1 <= t0`, non-finite numbers, `budget` not a positive integer,
non-positive `atol`/`rtol`, `n_points < 2`, unknown fields are fine but the 
required ones must be sound), then:

- Print a single line to **stderr** starting with `ERR: ` followed by a short
  human-readable reason.
- **Exit with a non-zero status** (e.g. `1`).
- Do **not** leave a valid output file at `<out.json>` (you may leave nothing,
  or remove any partial file you created).

---

## 2. `/app/eig.py`

Two subcommands.

### 2a. Largest-magnitude eigenvalue

```
python3 /app/eig.py largest <A.json> <out.json>
```

`<A.json>` holds a real-or-complex square matrix `A` (`2 <= n <= 8`). Compute the
**eigeneigenvalue of `A` with the largest magnitude** (modulus). Magnitude ordering
means `|lambda| = sqrt(re^2 + im^2)`; you must order by magnitude, NOT by real part.

Write `<out.json>`:

```json
{ "re": 0.5, "im": -2.0, "mag": 2.0607 }
```

where `re`/`im` are the real/imaginary parts of the selected (possibly complex)
eigenvalue and `mag` is its exact modulus (same as `hypot(re, im)`). If several
eigenvalues tie in magnitude, any one of the maximum-magnitude set is acceptable.
Return reasonable precision (you are compared against a scipy `eigvals` recompute
with tolerance `1e-7`).

### 2b. Principal-minor spectra

```
python3 /app/eig.py principal <A.json> <out.json>
```

For a square `n x n` matrix `A`, the **k-th leading principal minor** is the
`k x k` submatrix `A[0:k][0:k]` (the top-left `k` rows and columns). Compute, for
each `k = 1 .. n`, the eigenvalues of that minor.

Write `<out.json>`:

```json
{ "spectra": [ [[re,im],[re,im],...], [[re,im],...], ... ] }
```

- `spectra` is a list of length `n`: `spectra[k-1]` holds the eigenvalues of the
  `k x k` leading principal minor, so the first element has 1 eigen-species, the
  last has `n`.
- Each eigen-species `spectra[k-1]` is ordered by decreasing magnitude; ties are
  broken by decreasing real part then decreasing imaginary part. Each entry is a
  `[re, im]` pair.

Consume the (complex-valued) eigenvalue arrays from each minor and emit the
per-index spectra row reconstructed as above. Constants may be compared with
`1e-8` tolerance.

### Malformed input

The same `ERR:` behavior as integrate.py applies: a non-square/no/`n` outside
`2..6`/non-numeric matrix → print `ERR: ...` to stderr, non-zero exit, and do not
leave a valid `<out.json>`. For `eig.py` a wrong-looking `n` out of range
`2..8` is also a malformed case.

---

## Edge cases the grader probes

- **Tight budget / hard ceiling**: integrator on systems of different stiffness
  and spans; you must not exceed `budget` calls.
- **Randomized initial states**: robustness to different `y0` (never diverge,
  never `NaN`/`Inf`).
- **Non-symmetric matrices with complex eigenpairs**: the largest-magnitude
  select must handle conjugate pairs and negative real spectra (a naive
  'largest real part' chooses the wrong eigenvalue).
- **Lead-major spectra**: check each `k` block reconstructed and magnitude-sorted.
- **Malformed / tricky inputs**: missing fields, wrong shapes, `t1 <= t0`,
  non-square matrices, bad `budget`/`atol`/`rtol`. These must be reported cleanly
  with `ERR:` and a non-zero exit.

Precision tip: keep `n_points` modest; the grid length is what the grader
compares and big grids are fine but unnecessary.

Write robust, self-contained, deterministic scripts. Then leave them at
`/app/integrate.py` and `/app/eig.py`.