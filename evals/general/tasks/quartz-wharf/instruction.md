# Floatwork: an ODE/IVP and spectral toolbox

You are working for a coastal-hydrodynamics consultancy, **Quartz & Wharf Marine Analytics**.
The modelling team needs a small, self-contained numerical toolbox in `/app` that they can
point at new wave, current and mooring systems. The toolbox has three artifacts:

1. `/app/integrate.py` — a single- and batch-mode adaptive initial-value-problem (IVP) integrator.
2. `/app/eig.py` — dominant-eigenvalue and principal-minor-spectra helpers.
3. `/app/bench.py` — a runnable comparison script that generates synthetic portfolios and
   reports serial-vs-parallel correctness and relative performance.

Build all three. They are the deliverables that get executed and checked. Work only with
`numpy` and `scipy`; both are installed.

---

## 1. `/app/integrate.py`

Implement a numerically-correct adaptive IVP integrator. You must write the marching logic
yourself (adaptive step-size control of your choice — Richardson step-doubling, embedded
RK pairs, etc.). You may use `scipy` for **validation/chores** but the actual stepping must be
your own code driven by the RHS callback you are handed (the verifier injects RHS functions
and counts every call it makes).

Expose exactly these two functions:

```python
import numpy as np

def integrate(rhs, ts, y0, budget=None, atol=1e-4):
    # -> np.ndarray of shape (K, D)  where K = len(ts), D = len(y0)
    ...
    return Y

def integrate_many(rhs, ts, Y0, budget=None, atol=1e-4):
    # -> np.ndarray of shape (M, K, D)   where M = Y0.shape[0], K = len(ts)
    ...
    return YY
```

Semantics

- `ts` is a 1-D `np.ndarray` of sample times (strictly increasing; `ts[0]` is the initial
  time). The solver must return a state at **every** entry of `ts`, with `Y[0] == y0`.
  `ts` need not be uniform — coarse and finely spaced samples can blend.
- `rhs` is the right-hand side of `dy/dt = rhs(t, y)`:
  - For `integrate`, `rhs(t, y)` receives a Python float scalar `t` and a 1-D array `y`
    of shape `(D,)` and must return shape `(D,)` (elements may depend on the full state).
  - For `integrate_many`, `rhs(t, Y)` receives `t` and `Y` of shape `(M, D)` (all `M`
    instantaneous states) and must return shape `(M, D)` element-wise. Your batch integrator
    is expected to evaluate the RHS in a **vectorized/batched** way across the `M` states.
- `y0` / `Y0` hold the initial state(s). Finite, possibly mixed-sign floats.
- `atol` is an absolute tolerance: your output state at every sample must satisfy
  `max_i max_j |Y[i,j] - Yref[i,j]| <= atol`, where `Yref` is a very accurate reference
  (computed for you by the verifier with a far stricter method). Your internal strategy needs
  margin so this passes; a good target is to keep your own local error well below `atol`.
- `budget` is an optional hard ceiling on **how many times your code may evaluate `rhs`**.
  The verifier wraps the RHS in a counter and aborts scoring if the count goes over the
  ceiling **before returning**. Step-doubling / error-checking calls count, so design an
  adaptive scheme (a coarse fixed stepper that floods evaluations, or one that refuses to
  shrink its step, will blow the ceiling or the accuracy — you must trade between them).

Robustness requirements (all hidden cases probe these):

- **No NaN / Inf.** If a trial step would produce a non-finite intermediate state, your
  controller must shrink the step and re-try rather than march through it. The final `Y` must
  be all finite.
- **Hard evaluation budget.** Respect `budget` (when provided): for the hidden systems the
  ceiling is roughly 2–3× the number of RHS calls a tidy adaptive integrator needs. A naive
  blast of tiny fixed steps blows the ceiling; a greedy coarse stepper blows accuracy.
- **Stiff-ish and high-frequency dynamics.** The hidden RHS family includes: a damped
  nonlinear pendulum (`y'' = -g·sin(y) - c·y'`) with many randomized initial states; a van der
  Pol oscillator; a linear high-frequency rotation (`y'' = -ω²y`) sampled on a *coarse
  non-uniform* grid; and a stiff scalar `y' = -k·(y - sin(t))` on a *two-point* grid. A
  controller that only accepts/refines from the previous step quickly builds the needed
  step density, but it must also know when it cannot cheaply reach the endpoint accuracy.
- **Randomized portfolios.** `integrate_many` is exercised over dozens of randomized initial
  states with the *same* RHS; every row must independently meet the accuracy/NaN/budget rules.

### Make `integrate_many` genuinely faster than a serial loop

The verifier independently times **M calls to `integrate`** against **one call to
`integrate_many`** on the same portfolio (a damped pendulum with `M` randomized states over
60–200 samples). Your batched path must run **at least 2× faster** than that serial loop and
must produce nearly identical results to the serial path (it takes the same trajectory as
`integrate`, just vectorized across states). Use batched/vectorized stage evaluations (the
steps are accepted/shared across all rows) so you actually get the speed-up. This matters:
these two paths must agree *and* the batched path must be measurably quicker.

---

## 2. `/app/eig.py`

Implement two spectral helpers, exact signatures:

```python
import numpy as np

def dominant(M):
    # -> complex
    ...

def spectrum_row(M, k):
    # -> list of complex   (length k)
    ...
```

Contract:

- `dominant(M)`: `M` is a square `(n, n)` real (non-symmetric in general) matrix. Return the
  **actual** eigenvalue of `M` with the largest magnitude `|·|` (vector magnitude, so complex
  and real eigenpairs are both meaningful). If the largest eigenvalue happens to be real and
  negative, return a negative real value — **do not** return its absolute value. Ties in
  magnitude are avoided in the tests; the value you return must match the reference within the
  round-to-round relative tolerance (1e-6 on real and imaginary parts) *and* match the
  maximum magnitude.
- `spectrum_row(M, k)`: with `k` between 1 and n. Return a Python list of length `min(k, n)`:
   the `m`-th element is the dominant eigenvalue (largest-magnitude) of the **leading
  principal submatrix** `M[:m, :m]` (top-left `m×m` block), for `m = 1 .. min(k,n)`. This
  "reconstructs a row of the principal-minor spectra" of `M`. The reference verifier computes
  the same quantities itself with `numpy.linalg.eigvals` on each submatrix.

Robustness: the matrices are real, generally non-symmetric, and may have complex eigenpairs
(rotation-like blocks). Handle a large dynamic range of magnitudes (e.g. 1e-6 up to 1e6)
and an `n` up to ~600. Return Python `complex` values.

`dominant` should also be reasonably efficient: the verifier checks it completes a
`n ≈ 400` matrix workload within a fixed multiple (≈15×) of the time `numpy.linalg.eigvals`
takes on the same matrix. A direct `np.linalg.eigvals` based implementation passes trivially.

---

## 3. `/app/bench.py`

A **self-contained runnable script** (`python3 /app/bench.py`, exits 0). It must:

1. **Generate synthetic data**: build a synthetic set of, say, `M = 24` randomized damped-
   pendulum initial states over a common time grid (any rational grid you choose; the point is
   that the data is programmatically generated, not hard-coded).
2. **Run both the serial and the parallel/vectorized path** on that data: the serial path is
   `M` calls to `integrate`; the parallel path is a single `integrate_many` call.
3. **Compare correctness** (max absolute difference between the serial and batched final
   states) and **measure relative performance** (serial time / batched time).
4. **Print a machine-readable report** to stdout with these exact keys, one per line:

   ```
   portfolio=<int>
   correct=<float>     # 1.0 - max_abs_diff ... so 1.0 means exact agreement
   speedup=<float>     # serial_time / batched_time  (> 1 means batched wins)
   nthreads=vectorized-batch
   ```

The verifier parses these lines, requires `correct >= 0.9995`, `speedup > 1.5`, and exit
status 0. (You may print other explanatory lines too; only the keyed lines are read.)

---

## Package layout and what is checked

Create exactly:

- `/app/integrate.py` — functions `integrate` and `integrate_many`.
- `/app/eig.py` — functions `dominant` and `spectrum_row`.
- `/app/bench.py` — runnable report script.

The verifier will:
- `- import` all three modules;
- run `integrate` / `integrate_many` on several hidden IVP systems (the four families above,
  incl. randomized-state portfolios, coarse log/non-uniform 2-point grids) and compare to a
  DOP853 reference within `atol`, enforce the eval-count ceiling with a counting wrapper, and
  require all-finite output;
- time the serial vs batched paths and assert ≥ 2× speed-up;
- run `eig.dominant` and `eig.spectrum_row` on non-symmetric matrices with complex eigenpairs
  and mixed-scale magnitudes, compare to `np.linalg.eigvals` references, and check the
  `n≈400` runtime bound;
- run `python3 /app/bench.py` and parse the report keys.

You must not change any environment- or package-level settings or try to cache the RHS
counter. Deliver all three files under `/app` before the session ends.

## Hints that will save you time

- Validate your solver against `scipy.integrate.solve_ivp(..., method='DOP853', rtol=1e-11,
  atol=1e-13)` — that is the accuracy floor the verifier uses for the reference. If your
  output is within a hair of it at significant sample points, you are on the right track.
- Write `integrate` first with a robust adaptivity controller; reuse the exact same per-stage
  strategy in `integrate_many` but broadcast the rows so a single batched RHS call computes
  every state at once.
- Keep the `bench.py` output invariant/independent of run-to-run timing: it reports the
  measured ratio; just be consistent about using a large-enough portfolio that the ratio is
  meaningful (≥ 24 states, 100+ grid samples).