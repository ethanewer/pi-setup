# Umber Terrace: a numeric-optimization toolbox

You are provisioning a small numeric-optimization toolbox in a Linux image
(`Python 3.12`; `numpy`, `scipy`, `pulp`, `highspy` and `ortools` are already
installed — use them freely). Everything lives under `/app`.

The toolbox is **four independent command-line Python tools**. Each tool reads
an **instance input file** given as a command-line argument, does the real
numerics on it, and writes an **output file** to a second given path. For each
tool you must also run it once on a ready-made sample instance that is already
located under `/app`, so the generated output file lives on disk too.

The verifier will afterwards call **your exact tool programs** on **new hidden
instances of identical shapes** and check the numbers you compute, so every tool
must be a real, general, runnable interface — never a hard-coded one-off. Do not
print anything except the required output file (no stray stdout). Keep paths
literal under `/app`.

What the hidden cases probe (all documented here so your programs must handle
them):

* **MIP:** one hidden model is a pure *linear* program, another a *fully
  integer* MIP (all-integer columns, covering rows). Column bounds and row
  senses come from the MPS `BOUNDS` section.
* **Corners:** one hidden LP has several corners; the other is *degenerate* —
  two different column-subsets give the *same* vertex (count it once) and at
  least one column-subset is singular (skip it). Only nonnegative solutions are
  valid.
* **Quartic:** a large-scale instance with `n = 120`.
* **Sinkhorn:** a larger cost matrix (rows x cols ~ 45x65) that must converge
  quickly.

---

## 1. Mixed-integer programming solver

```
python3 /app/solve_mip.py <MODEL.mps> <OUT.json>
```

`<MODEL.mps>` is a standard **minimization** LP/MPS model. It may be a pure LP
(all columns continuous) or an integer program (columns marked with MPS
`INTORG/INTEND` marker sections). Reads `NAMES`, `ROW`, `COLUMN`, `RHS`, and
`BOUNDS` sections; use those bounds and senses as given.

Read it, optimize, and write `<OUT.json>`:

```json
{
  "optimal": true,
  "status": "Optimal",
  "objective": 63.264301,
  "x": { "X0": 13.0, "X1": 0.0, "X2": 15.0, "X3": 0.0, "X4": 0.0, "X5": 0.0 },
  "ncols": 6,
  "nrows": 4
}
```

- `"x"` maps each column name (exactly as written, e.g. `X0`) to its primal
  value at the optimum.
- `"optimal"` is `true` only at an optimal solution.
- Use a real library solver (HiGHS `highspy`, `pulp` / CBC, or
  `scipy.optimize.milp`). The verifier cross-checks the objective and every
  variable value against an independent solver.

Sample run:

```
python3 /app/solve_mip.py /app/model.mps /app/mip_result.json
```

`/app/mip_result.json` is your solver's output for `/app/model.mps`.

---

## 2. Enumerate corner solutions of a nonnegative linear program

```
python3 /app/corners.py <INPUT.json> <OUTPUT.txt>
```

`INPUT.json`:

```json
{
  "A": [[1, 0, 1, 0], [0, 1, 0, 1]],
  "b": [1, 3],
  "tol": 1e-9
}
```

`A` has `m` rows and `n` columns (`n >= m`); `b` has length `m`. Consider the
region `A·x = b`, `x >= 0`, and enumerate **every corner (basic feasible
solution)**:

1. Take every subset of exactly `m` of the `n` columns.
2. Solve the square system `A[:, cols] xtilde = b` for that subset.
3. If that subsystem is singular, skip it entirely.
4. If any component of `xtilde` is `<- tol`, skip it (nonnegativity).
5. Build the full `n`-vector: values at the chosen columns equal `xtilde`,
   the rest are zero.
6. Collapse duplicates: two different column-subsets may yield the same full
   vector — keep each distinct vector **once**.

Write `<OUTPUT.txt>`:

```
COUNT
x_0 ... x_{n-1}
x_0 ... x_{n-1}
...
```

Line 1 is the integer `COUNT` (number of distinct corners), then one corner per
line as a space-separated nonnegative vector.

Sample run:

```
python3 /app/corners.py /app/instance_corners.json /app/corners.txt
```

---

## 3. Quartic + quadratic-penalty + coupling minimization

```
python3 /app/quartic_min.py <INPUT.json> <OUT.json>
```

Find a near-stationary point of

```
f(x) = Σ_i  p_i (x_i - u_i)^4                      (per-variable quartic)
     + Σ_g  a_g ‖x[{groups_g}] - m_g‖²          (per-vector quadratic penalty)
     + ½ xᵀ Q x                                 (global quadratic coupling)
     + lᵀ x                                     (optional linear term)
```

`INPUT.json` fields: `n`, `u`, `p` (quartic center/weight per variable),
`groups` (a list of index-subsets partitioning variables into vectors), `a` (a
weight per group), `m` (a center vector per group), `Q` (a symmetric `n x n`
coupling matrix), `l` (linear coefficients, optional), `seed`.

Write `<OUT.json>`:

```json
{
  "solution": [x_1, ..., x_n],
  "objective": 126.451139,
  "grad_norm": 0.0009
}
```

`solution` must reach a near-stationary point (gradient norm small). Use a
derivative-based optimizer (`scipy.optimize.minimize` with a `jac`, e.g.
L-BFGS-B); random restarts are allowed. `objective` is `f(solution)`, and
`grad_norm` is the Euclidean norm of the gradient at `solution`.

The verifier computes its own minimum of the same objective and also re-evaluates
your `solution` on its own copy of `f`, so the reported point and number must be
consistent.

Sample run:

```
python3 /app/quartic_min.py /app/instance_quartic.json /app/quartic_solution.json
```

---

## 4. Entropic-regularized Sinkhorn transport

```
python3 /app/sinkhorn.py <INPUT.json> <OUT.json>
```

`INPUT.json`:

```json
{
  "C":  [[...]],
  "a":  [0.20, 0.50, ...],
  "b":  [0.10, 0.40, ...],
  "eps": 0.1,
  "target": 1e-9,
  "max_iter": 20000
}
```

`C` is a nonnegative `m x n` cost matrix; `a` (`m`) and `b` (`n`) are positive
marginals (you should normalize them to sum 1 if the verifier needs to). The
plan `P >= 0` satisfies `P·1 = a` and `Pᵀ·1 = b` and minimizes
`Σ P_ij C_ij + eps Σ P_ij (log P_ij - 1)`. Compute it with the standard Sinkhorn
scaling iteration: `K = exp(-C/eps)`, `u = a/(K v)`, `v = b/(Kᵀ u)`, repeated
until the row and column marginals of `diag(u)·K·diag(v)` are both within
`target`. Never exceed `max_iter` (bounded so it finishes within the budget).

Write `<OUT.json>`:

```json
{
  "cost": 1.118792,
  "iterations": 107,
  "converged": true,
  "plan": [[...], [...]]
}
```

`cost = Σ P·C`. The verifier checks the cost against its own Sinkhorn value,
checks your `plan`'s marginals match `a`/`b`, and times your run.

Sample run:

```
python3 /app/sinkhorn.py /app/instance_sinkhorn.json /app/ot_cost.json
```

---

## Required deliverables (every path must exist under /app)

| file | what it is |
|---|---|
| `/app/solve_mip.py` | program 1 |
| `/app/mip_result.json` | its output on `/app/model.mps` |
| `/app/corners.py` | program 2 |
| `/app/corners.txt` | its output on `/app/instance_corners.json` |
| `/app/quartic_min.py` | program 3 |
| `/app/quartic_solution.json` | its output on `/app/instance_quartic.json` |
| `/app/sinkhorn.py` | program 4 |
| `/app/ot_cost.json` | its output on `/app/instance_sinkhorn.json` |

All sample inputs `/app/model.mps`, `/app/instance_corners.json`,
`/app/instance_quartic.json`, `/app/instance_sinkhorn.json` are already present.

Do not modify anything outside `/app`. Leave tools runnable as `python3 <path>`
and produce every output by actually solving the given input — no hard-coded
results.