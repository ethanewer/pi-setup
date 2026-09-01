# Nectar Gasket — garden-trajectory & spectral pipeline

## Goal

A small dynamics cell ("Nectar") maintains a numerical toolkit for its **garden-swan**
model: a fleet of bodies sliding along a line under a coupled relaxation law, plus a
separate spectral-analysis library for non-symmetric "asset" matrices. You must build
two executable Python programs and one derived report:

- `/app/integrate.py` — the garden-swan ODE integrator.
- `/app/eig.py` — the spectral tools.
- `/app/metrics.json` — a speed-report written by running the *parallel* ensemble
  (produced by your own code, described below).

All numeric outputs are compared against an independently computed fine-grained
reference and must match within a documented absolute tolerance. A correct run also
keeps two physical-closeness metrics above thresholds and stays finite everywhere.

## Environment

- Python 3.12 with `numpy` and `scipy`; `WORKDIR` is `/app`.
- Shipped (read-only reference data, already present):
  - `/app/sample_garden.json` — a small garden + ensemble case (see schema below).
  - `/app/eig_fixtures/assets_1400.npy` — a 1400×1400 non-symmetric double matrix
    (an saved `.npy`; load with `numpy.load`).

You may create any new files under `/app`. Do **not** modify or move the shipped
files listed above, and never read `/tests`.

## The ODE — "garden" family (fixed form)

State `u(t) ∈ R^n`. Each component `u_i` is one body's signed position. The vector
field is:

```
du_i/dt = alpha_i * (a_i - u_i)  -  c_i * sum_{j != i} (u_j - u_i) / ( (u_j - u_i)^2 + eps^2 )
```

where `a` is the (strictly increasing) "anchor" of each body, `alpha` and `c` are
positive per-body coefficients, and `eps` is a small positive softening length. The
`a`/`alpha`/`c`/`eps` arrays/scalars are given in each case. Anchors are placed 1 unit
apart and coupling is short-range, so bodies relax near their anchors and stay
separated; the positive infimum of the two nearest bodies is governed by the anchor
spacing.

## Case JSON schema (used by `integrate.py`)

```json
{
  "id": "case-name",
  "ode": {
    "n": 64, "a": [...n...], "alpha": [...n...], "c": [...n...], "eps": 0.02,
    "y0": [...n...], "t0": 0.0, "tmax": 1.0, "M": 21,
    "tol": 5e-5, "budget": 200000,
    "thresholds": {"min_norm_dist": 0.005, "avg_norm_dist": 0.1}
  }
}
```

`M` is the number of output times forming an even grid `t0 .. tmax` (so
`M>=2`; `M-1` grid intervals). `tol` is the **absolute** accuracy target.
`budget` is a hard cap on the number of RHS evaluations your program performs.

## `integrate.py` commands

You must support exactly these three CLI forms (called by the grader as
`python3 /app/integrate.py ...`):

1. `python3 /app/integrate.py trajectory <case.json> <out.json>`
   Integrate the case ODE from `t0` to `tmax` starting at `y0` and write a trajectory
   sampled at the `M` grid times.
2. `python3 /app/integrate.py ensemble <case.json> <out.json>`
   Run the ensemble (see below): the per-sub-sample randomized workloads both in one
   process and across `n_jobs` worker processes, then compare & time them.
3. (when a single argument form is useful) support running with no extra step.

Any step-size policy is allowed — fixed-step RK4, adaptive Runge-Kutta, Dormand–Prince,
etc. — subject to the three correctness rules below.

### Output schema for `trajectory`

```json
{
  "id": "...",
  "tgrid": [M reals],
  "states": [[n reals], ... M rows ...],
  "eval_count": <int>,
  "metrics": {
    "min_norm_dist": ...,
    "avg_norm_dist": ...,
    "char_len": ...,
    "finite": true
  }
}
```

`states[k]` is the state at `tgrid[k]`. `eval_count` is the total number of RHS
evaluations your solver used (for RK4 with `s` steps over `n` rows this is `4*n*s`;
count whatever you actually call).

### The three correctness rules (these are what get checked)

**Rule 1 — trajectory accuracy.** For every grid time, the max absolute error versus
an independent fine reference of the SAME field must be `<= tol`. A coarse method
(e.g., Euler or a wide fixed step) will drift past the tight tolerances used in the
harness (orders `1e-5` .. `3e-5`); a correct RK4/adaptive solver with a properly chosen
step meets them comfortably. Because your `eval_count` is capped by `budget`, pick a
step that is fine enough for `tol` yet stays under `budget`.

**Rule 2 — physical validity (metrics).** From your sampled trajectory compute
`char_len = max_{i,j} |a_i - a_j|` (for fewer than 2 bodies use `1.0`), and for every
body pair `(i,j)` and every output time:
`d_ij(t) = |u_i(t) - u_j(t)| / char_len`. Then
- `min_norm_dist` = the minimum of all `d_ij(t)`;
- `avg_norm_dist` = the mean of all `d_ij(t)`;
- for fewer than 2 bodies both are `inf` (vacuous).
Your result must satisfy `min_norm_dist >= thresholds.min_norm_dist` and
`avg_norm_dist >= thresholds.avg_norm_dist` (given in the case), be finite, and its
`finite` must be `true`. A correctly integrated case passes these by a wide margin; a
divergent or NaN-bearing run fails them.

**Rule 3 — eval-count ceiling.** `eval_count` must be `<= budget` and all numbers must
be finite.

## The ensemble + parallel report

`ensemble` implements the per-`k` subsample workload split (competency:
parallelize across processes). The case carries:

```json
"ensemble": {"K": 16, "n_jobs": 4, "master_seed": 101, "noise": 0.05}
```

For subsample `s = 0 .. K-1`, derive an initial state deterministically:
`rng = numpy.random.default_rng(master_seed*7919 + s)`, `y0_s = sort(a + rng.normal(0, noise, n))`.
Each subsample is a full `trajectory` integration on that `y0_s`; keep the final-state
vector (at `tmax`) plus that run's two physics metrics.

- **serial variant**: do all `K` subsamples in the current process, in order.
- **parallel variant**: do the same `K` subsamples across `n_jobs` real worker
  processes (e.g. `concurrent.futures.ProcessPoolExecutor` / `multiprocessing`).
  Record for every subsample the worker PID under which it ran.

Output schema:

```json
{
  "n_jobs": 4,
  "sequential": {"seconds": ..., "pids": [...], "distinct_pids": ..., "min_norm_dist": ..., "avg_norm_dist": ...},
  "parallel":   {"seconds": ..., "pids": [...], "distinct_pids": ..., "min_norm_dist": ..., "avg_norm_dist": ...},
  "max_parallel_serial_abs_diff": ...,
  "speedup": ...
}
```

Rules that are checked on `ensemble`:

- The parallel per-subsample results must equal the serial ones: the max absolute
  difference over every subsample's final-state vector must be `<= 1e-6`
  (deterministic because the subsample seeds are identical in both variants).
- The parallel variant must genuinely use more than one process:
  `parallel.distinct_pids >= 2` (a fake "parallel" that only loops in one process will
  report `distinct_pids == 1`). If `K >= n_jobs`, expect `distinct_pids ~= n_jobs`.
- Both `parallel.seconds` and `sequential.seconds` must be present, finite and `> 0`;
  `speedup` must be finite and `> 0`. WAIT: your parallel and serial physics metrics
  (`min_norm_dist`, `avg_norm_dist`) must be finite and equal each other within
  `0.01` (agreement across variants), and must also exceed a small floor.
- `n_jobs` must equal the requested value.

## `/app/metrics.json`

Produce `/app/metrics.json` at build-verify time by running
`python3 /app/integrate.py ensemble /app/sample_garden.json /app/metrics.json`
(this writes the ensemble output to `/app/metrics.json`). The file must contain the
two time keys `sequential.seconds` and `parallel.seconds`, and a `speedup` key. It is
a real checked deliverable.

## `app/eig.py` — spectral tools

Two functions plus CLI `python3 /app/eig.py <in.json> <out.json>`.

`in.json` is either
```json
{"matrix": [[...nested n x n reals...]], "do_pm": true}
```
or
```json
{"file": "/app/eig_fixtures/assets_1400.npy", "do_pm": false}
```

`out.json`:
```json
{
  "dominant": [real, imag],
  "dominant_mag": <abs>,
  "size": n,
  "principal_minor_spectra": [[re,im], ...]        // only when do_pm is true
}
```

**Dominant eigenvalue selection (exact deterministic rule).** For matrix `A`, let
`w = scipy.linalg.eigvals(A)` (a complex vector; `A` may be non-symmetric and have
complex eigenpairs). Pick the entry maximizing, lexicographically,
`(|w| ,   Re(w) ,   -|Im(w)|)`. That is, among equal magnitudes prefer the larger real
part, then the smaller absolute imaginary part. Return that complex eigenvalue. This
selection rule must match byte-wise any independent recomputation.

**Principal-minor spectra (the "row").** For `do_pm`, return a 1-D row whose `j`-th
element (0-based) is the dominant eigenvalue of the leading principal minor `A[:j+1, :j+1]`
using the same selection rule. Works for `1×1` (returns that single value) up to
moderate sizes.

The big `assets_1400.npy` matrix exercises scaling to thousands of "assets": your
code must compute the correct dominant magnitude eigenvalue on a 1400×1400 non-symmetric
real matrix without memory failure or `NaN`, in an acceptable time. Libraries (numpy /
scipy LAPACK) are allowed; you must implement the selection/ordering logic yourself.

## Edge & malformed cases to handle (all graded)

- **Single body (`n == 1`)**: no pairs exist — return `inf`/`inf` for the two physics
  metrics, `finite: true`, and a correct trajectory (integrate the single ODE). Do not
  crash.
- **Two bodies (`n == 2`)**: a single pair; both metrics must be correct and
  `>= thresholds`.
- **Very small grids** (`M == 2`, only the two endpoints) and `tmax == t0`.
- **Tight tolerances** (`tol` down to `2e-5`) combined with finite `budget`: your
  step choice must still meet accuracy without exceeding `budget`.
- **A 1×1 eigen matrix**: dominant == that single value; principal-minor row is its
  length-one row of that value.
- **Eigen tie-break families**: matrices whose largest-magnitude eigenvalues are a
  complex conjugate pair (equal magnitudes) — the rule above must select deterministically.
- **The 1400×1400 fixture**: dominant eigenvalue correct and finite.

## Restrictions

- Compute only with `numpy` / `scipy` / Python standard library. Do not shell other
  solvers, no training data.
- Your programs must be runnable as CLI given above on NEW inputs (fresh sized, physics
  cases the grader will prepare) — the particle is to implement the general
  `integrate.py` and `eig.py`, not to hard-code a single number.

## Local verification (how to prove it yourself)

1. Run `python3 /app/integrate.py trajectory /tmp/mycase.json /tmp/out.json` on a few
   cases you invent (varied `n`, tight `tol`, small `budget`, `n==1`, `n==2`) and
   inspect accuracy by comparing with a very-fine step of the SAME field and the
   budget/physics rules above.
2. Run `python3 /app/integrate.py ensemble /app/sample_garden.json /app/metrics.json`
   and check the serial/parallel agreement, PID counts, and reported times.
3. Run `python3 /app/eig.py` on small matrices with complex pairs and on the shipped
   `assets_1400.npy`, and verify the dominant selection and principal-minor row by
   recomputing with the documented rule.
4. Run your programs with no special environment; everything must be computed at
   runtime (the grader will re-run both scripts on fresh hidden inputs).

## Success criteria

- `/app/integrate.py` and `/app/eig.py` exist and are executable.
- `trajectory` meets Rule 1 + 2 + 3 on every graded case (visible and hidden).
- `ensemble` produces identical physical results across variants, uses real
  multi-process parallelism, and reports plausible finite timings.
- `/app/metrics.json` contains `sequential.seconds`, `parallel.seconds`, `speedup`.
- `eig.py` finds the correct dominant eigenvalue and principal-minor row on small,
  complex-spectra, singleton, and large-scale inputs.