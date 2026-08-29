# Quartz-delta: numerical kernels

You are handed a research library in progress. It must grow a set of **standalone numerical
kernels** that are exercised later inside a Docker container on a battery of fresh, hidden
inputs — empty/single-point/tiny point sets, a fresh symmetric matrix, and new ODE output
times. Every kernel must therefore be **general-purpose**: driven by its inputs, not by any
assumed shape or fixed value.

Everything you build lives in a single importable module `/app/kernels.py`. The grader
imports that module and calls the four public functions specified below on hidden inputs. It
also reads the output file `/app/out.npy` you must produce. Nothing else is graded.

No network access is available. `numpy`, `scipy`, and `sympy` are installed.

---

## Deliverable 1 — `/app/kernels.py`

A module exposing exactly these four public functions:

```python
compute_wasserstein_distance(a, b, method="exact", bins=24) -> float
compute_wasserstein_grid(a, b, bins=24) -> float
reconstruct_eigenvector_components(A) -> np.ndarray
ode_solve_landing(rhs, t0, t_end, eval_times, y0, step=0.05) -> dict
```

`a` and `b` are empirical point clouds: array-like of shape `(n, d)` and `(m, d)` for any
dimension `d >= 1`. A `(n,)` 1-D array is treated as `(n, 1)` (points on the real line).
Treat every point as an equally-weighted atom of the empirical measure.

### Kernel A — `compute_wasserstein_distance`

Main interface for a 1-Wasserstein (Earth-Mover) distance between two empirical measures,
with Euclidean ground metric.

* `method="exact"` — solve the optimal-transport linear program exactly (mass `1/n`, `1/m`,
  minimize transport cost); this is the authoritative value.
* `method="grid"` — dispatch to `compute_wasserstein_grid(a, b, bins=bins)` and return that
  grid approximation. This is the ONLY grid dispatch point.

Edge cases that must hold for **both** methods (and for the standalone grid function):

* **Empty cloud** — if `len(a) == 0` or `len(b) == 0`, raise `ValueError`.
* **Identical clouds** — if the two point sets are identical, return `0.0`.
* **Single points** — if each cloud has exactly one point, return the Euclidean distance
  between them.
* **Symmetry** — `compute_wasserstein_distance(a, b)` and `compute_wasserstein_distance(b, a)`
  must be equal (to floating noise).

### Kernel B — `compute_wasserstein_grid(a, b, bins=24)`

A **grid-approximation** path: histogram both clouds onto a shared axis-aligned grid, then
run an entropic (Sinkhorn) iterative coupling on the low-dimensional grid histograms and
return the resulting transport cost. It must:

* Be a genuinely independent path from the exact LP (histogramize both clouds on the grid;
  run Sinkhorn on the grid coupling).
* Keep the returned value within the required tolerance band of the exact 1-Wasserstein
  (`error <= 0.20 * exact + 0.05`) for the seeded/continuous test data. A coarse histogram
  with too few bins, or an unterminated Sinkhorn, will drift outside this band.
* Honor the same three degenerate behaviors as Kernel A (empty -> `ValueError`; identical ->
  `0.0`; single points -> Euclidean).

Suggested recipe (matches the shipped mesh and passes the band):

1. Build one set of grid edges covering the combined range of `a` and `b`, padded by `5%` on
   each side, with `bins` interior points per dimension. Use the cell midpoints as cell
   coordinates.
2. Equal-weight each point and count how many points fall in each grid cell, giving a
   histogram over the grid for each cloud.
3. Set `epsilon = 0.1 * median(positive pair distances)` and compute the Gibbs kernel
   `K = exp(-distance / epsilon)`. Iterate Sinkhorn primal scalings for `100–200`
   iterations. Return `sum(T * C)` where `T = u[:, None] * K * v[None, :]`.

### Kernel C — `reconstruct_eigenvector_components(A)`

Given a square **symmetric** matrix `A` with `n` distinct eigenvalues, return an `(n, n)`
real array whose column `k` holds the **absolute values** `|v_ki|` of the orthonormal
eigenvector associated with the `k`-th **smallest** eigenvalue (`k` ascending, i.e. matching
`np.linalg.eigh`'s column ordering). The values are well-defined and the sign ambiguity is
removed by taking absolute values; each column must be normalised to unit norm.

This kernel must be a genuine *paper-style reconstruction*: you take the spectrum
(eigenvalues) of `A`, then for each eigenvalue `lambda_k` reconstruct the eigenvector
magnitudes from the matrix and that spectrum — e.g. via the scaled spectral projector

```text
P_k = ( prod_{j != k} (A - lambda_j I) ) / ( prod_{j != k} (lambda_k - lambda_j) ) = v_k v_k^T,
|v_ki| = sqrt( P_k[i, i] )
```

Do **not** simply return the eigenvector columns that `np.linalg.eigh` produces; reconstruct
the magnitudes from the spectrum (you may compute that spectrum with `eigvalsh`). The output
must match `abs(eigenvector matrix)` from `np.linalg.eigh` to ~`1e-6`.

Raise `ValueError` if `A` is not square, or not symmetric. (It is given that the hidden
matrices have distinct eigenvalues.)

### Kernel D — `ode_solve_landing(rhs, t0, t_end, eval_times, y0, step=0.05)`

Integrate a right-hand side `dy/dt = rhs(t, y)` from `t0` to `t_end`, starting from `y0`, and
**return the solution at each prescribed output time with the risky requirement that the
right-hand side is evaluated *exactly at* every prescribed time** — no interpolation used
for outputs.

You must implement your own explicit integrator (a 4th-order Runge–Kutta / RK4 stepper is
fine) — **using `scipy.integrate` (e.g. `solve_ivp`, `odeint`) to produce the trajectory is
forbidden**. To land on an output time, each internal substep is sized so that it ends
exactly there: when the time point `t_prev + step` would overshoot a prescribed `t_eval`,
clamp the final substep to exactly `t_eval - t_prev`, so an `rhs` call happens at
`t_eval` in that final substep. `eval_times` is an array within `[t0, t_end]`.

Return a dict with exactly these keys:

```
{
  "eval_times": np.ndarray,   # the requested output times
  "y": np.ndarray,            # shape (len(eval_times), dim) solution at each eval time
  "rhs_times": np.ndarray,    # every time at which rhs(...) was called, including t0 and every eval time
}
```

`rhs_times` must include **each** `t_eval` (within `1e-8`) — proof that the right-hand side
was evaluated exactly at that time, never interpolated, and there must additionally be an
`rhs` call within one `step` **before** each `t_eval` (a short preceding integration gap).

---

## Deliverable 2 — `/app/out.npy`

`/app/fixture.npy` (a given 4x4 symmetric matrix, shipped in the container, do **not
modify** it) is the visible fixture. Produce `/app/out.npy` by *running* kernel C:

```python
import numpy as np
import kernels
A = np.load("/app/fixture.npy")
np.save("/app/out.npy", kernels.reconstruct_eigenvector_components(A))
```

`/app/out.npy` must equal `reconstruct_eigenvector_components(/app/fixture.npy)` (a `(4,4)`
array of positive magnitudes) to `1e-7`.

## Fixed inputs — do not modify

* `/app/fixture.npy` — the shipped symmetric fixture matrix.

Create only `/app/kernels.py` and `/app/out.npy` (you may add helper modules under `/app`).
Do not modify or remove `/app/fixture.npy`.

## Suggested sanity checks (your own, before you finish)

```python
import numpy as np, kernels
def gram(x): x=np.asarray(x,float); return x if x.ndim==2 else x.reshape(-1,1)
# exact / grid agree within band on a couple of nice 2-D sets; identical->0; empty raises
print(kernels.compute_wasserstein_distance(gram([[0.,0.],[1.,1.]]), gram([[2.,2.],[3.,0.]])))
print(kernels.reconstruct_eigenvector_components(np.array([[2.,1.],[1.,1.]])))
rhs=lambda t,y: np.array([-y[0]])
print(kernels.ode_solve_landing(rhs,0.0,1.0,[0.4,0.7,1.0],[1.0]))
```

The grader re-runs every kernel on fresh hidden inputs and compares to an independent
reference, so keep each function a general, deterministic, self-contained routine.