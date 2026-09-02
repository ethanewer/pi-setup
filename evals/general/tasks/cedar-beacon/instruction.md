# Cedar Beacon — slope-risk numeric pipeline

## Goal
The physics & risk cell at "Cedar Beacon" needs one reproducible numeric pipeline.
You must produce two deliverables:

- `/app/solve.py` — a Python program (module + CLI) that implements the whole pipeline
  described below.
- `/app/answer.json` — produced by running `/app/solve.py` with no arguments (see CLI).

All numeric outputs must match an independently computed reference within a relative
tolerance of `1e-6` (that is, `|a - b| <= 1e-9 + 1e-6 * |b|` for every scalar and every
element of every array).

## Environment / files present
- Python 3.12 with `numpy` and `scipy` installed; `gfortran` is installed.
- `/app/src/regen.f90` — a Fortran source file you must **compile and run** (see Part B).
- `/app/src/gamma.m` — a MATLAB source file you must **port to Python** (see Part C).

You may create files anywhere under `/app` (in particular make `/app/derived/`).
Do **not** modify, move, or delete anything under `/app/src`.

## Deliverable CL/C  /app/solve.py
`/app/solve.py` must parse the command line as follows:

- `python3 /app/solve.py <case.json> <out.json>` — read one case file, run the whole
  pipeline, write the result JSON to `<out.json>`.
- `python3 /app/solve.py` (no arguments) — run the pipeline on the built-in sample case
  (any realistic parameter set) and write `/app/answer.json`.

`<case.json>` has this exact schema:

```json
{
  "id": "case-name",
  "ode":    {"lam": [kA, kB, kC], "init": [A0, B0, C0], "tmax": 150.0, "steps": 1500},
  "gamma":  {"fin": [.. n numbers ..], "leak": 0.25},
  "risk":   {"values": [.. m numbers ..], "weights": [.. optional ..]}
}
```

The output `<out.json>` must have this exact schema (all numbers are JSON numbers):

```json
{
  "id": "case-name",
  "ode":     {"final_total": ..., "peak_total": ...},
  "gamma":   {"array": [.. n numbers ..], "scalar": ...},
  "risk":    {"attn": [.. m numbers ..], "attn_sum": ..., "score": ...},
  "regen":   "flag.txt present and non-empty"
}
```

Every field except `regen` is interpreted numerically; `regen` is an informational
string that this spec only requires non-empty. The verifier independently validates the
regenerator file (Part B) so the content of `regen` is not trusted.

## Part A — handwritten ODE integrator (a three-species decay cascade)
The cascade is a linear chain A -> B -> C with rate constants `lam = [kA, kB, kC]`:

```
dA/dt = -kA * A
dB/dt =  kA * A - kB * B
dC/dt =  kB * B - kC * C
```

with initial concentrations `[A0, B0, C0]` (all `>= 0`). Integrate from `t = 0` to
`t = tmax` using a **fixed-step classic 4th-order Runge-Kutta** with step `h = tmax/steps`
and exactly `steps` update loops. Track for each step the running total
`A(t)+B(t)+C(t)`.

Output:
- `final_total` = `A(tmax)+B(tmax)+C(tmax)` after all `steps` updates.
- `peak_total`  = the maximum of the running total over every update (including the
  initial value `A0+B0+C0`).

Constraints on the integration (non-negotiable):
- You must **write the RK4 stepper yourself**. You may import only the Python standard
  library and `numpy`.
- The following are **forbidden** and must not appear anywhere in `/app/solve.py`:
  `scipy.integrate`, `scipy.optimize`, `odeint`, `solve_ivp`, `sympy`, `torch`,
  `autograd`. (There is no "import a solver" escape hatch.)

### Part B — compile and run the Fortran regenerator
Compile `/app/src/regen.f90` with `gfortran`, then run the compiled binary passing a
single argument that names the output file **`/app/derived/flag.txt`**. Create
`/app/derived/` first if needed. After running, `/app/derived/flag.txt` must be
non-empty and its content must equal exactly what the compiled regenerator writes (a
12-line sum-of-squares series). Do not hand-write or `cat` this file — it must be
produced *by running* the compiled program.

### Part C — port the MATLAB routine
Read `/app/src/gamma.m`. It defines a function that, for a row input vector `fin`
(length `n >= 1`) and scalar `leak`, builds three "read paths" and merges them:

1. `a = (fin + leak) * 1.5` — leak-boosted control path (elementwise).
2. `b = flip(fin)` — the reversed (mirrored) input, elementwise.
3. `ramp` — a zero-initialized length-`n` vector whose **odd-indexed** (1-indexed)
   positions are copied from `fin`; even positions stay zero. (One-indexed odd means
   zero-based indices `0, 2, 4, ...`.)
4. `g = a + b + ramp` — elementwise sum of the three paths.
5. `gamma_scalar = sum(g) + g[0] + g[-1]` — the sum of `g` plus its two endpoints
   (this is the "endpoint concat" derived quantity).

You must implement this exact semantics in Python (function `gamma_path(fin, leak)`)
and return both `g` (the full array) and the scalar. Match within `1e-6` relative
tolerance, including for `n` of any size `>= 1` and for `leak = 0`.

### Part D — risk estimator (normalized softmax attention)
Implement `risk_attention(values, weights)` exactly as follows:

- `values` is a list of `m >= 0` floating values; `weights` is a list of 0 or `m`
  numbers. When `len(weights) != m`, treat weights as all `1.0`.
- If `m == 0`: return `attn = []`, `attn_sum = 0.0`, `score = 0.0`.
- Otherwise compute standard, **numerically stable** softmax attention over `values`:
  let `mx = max(values)`, `exp_i = exp(value_i - mx)`, then
  `attn_i = exp_i / sum_j(exp_j)`. `score = sum_i(attn_i * weight_i)`.
- `attn_sum = sum(attn)` which must equal `1.0` within `1e-9`.

Crucially this must stay **finite and normalized** in every regime the grader probes,
which includes: values near `0` (e.g. `1e-320`), very large magnitudes (e.g. `1e150`),
a single-instance bag (`m == 1` -> `attn = [1.0]`), variable bag sizes, lists that
contain a `0.0`, and the empty bag (`m == 0`). The max-subtraction form above is what
keeps the exponentials finite and the attention normalized.

## Edge & malformed inputs you must handle (these will be graded)
- Empty risk bag (`values == []`): must not crash; the defined outputs above apply.
- Single-instance bag (`values == [v]`): `attn = [1.0]`, `attn_sum = 1.0`.
- All-zero risk values: attention must be uniform (`1/m` each), `attn_sum == 1.0`.
- `weights` shorter/longer than `values`: ignored and replaced by all `1.0`.
- `steps == 0`/`tmax == 0`: the ODE must produce `final_total == peak_total == A0+B0+C0`
  (zero updates).
- `leak == 0` and any `n >= 1` for the gamma port.
- Every numeric result must be finite (no `nan`/`inf`) on all of the above.

## What must NOT be modified
- Nothing under `/app/src` (your deliverables read them only).
- Your output JSON files must contain exactly the schema keys above.

## Success criteria (how you prove it locally)
Run `python3 /app/solve.py /path/to/case.json /tmp/out.json` for several case files
(invent your own), and confirm each output field matches the formulas in Parts A-D to
the `1e-6` relative tolerance, that the regenerator file exists and matches the
compiled program's output, and that `solve.py` contains none of the forbidden imports.
Then run `python3 /app/solve.py` to produce `/app/answer.json`.
