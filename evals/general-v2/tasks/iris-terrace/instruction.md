# iris-terrace — scientific numerics fitting

You are working inside a Python 3.12 container. SciPy, NumPy and AstroPy are
installed. Build three standalone program deliverables under `/app` that solve
three independent numerical-modeling problems. The verifier will run each of
them, both on the provided visible data and on hidden fixtures it mounts, so
your programs must be self-contained, deterministic, and follow the exact
interfaces below.

Nothing under `/tests` exists in your environment; do not rely on it. Create
exactly these deliverables:

- `/app/fit_spectra.py`
- `/app/fit_results.json`
- `/app/stack_models.py`
- `/app/wasserstein.py`

---

## 1. Spectral peak fitting — `/app/fit_spectra.py`

A spectrum is stored as a plain text file with two columns `x y` (whitespace
or single-comma separated). One non-numeric header row may be present and must
be skipped; blank lines may be present and must be skipped. The `x` column is
monotonically increasing. The signal `y(x)` is the sum of several Lorentzian
peaks on a slowly-varying baseline, plus small random noise.

You must detect every peak, **crop a local window around each peak**, and fit a
single Lorentzian to that window:

    y(x) = offset + amplitude * width^2 / ((x - center)^2 + width^2)

using a `curve_fit`-style least-squares routine (SciPy's `curve_fit` is
recommended) with **sensible starting values**: center from the detected local
maximum, amplitude from the peak height above the window's baseline, offset
from the window's baseline level, and width from the window geometry. Fit each
peak in its own window (e.g. between the midpoints toward the neighbouring
peaks), then report the four parameters.

CLI (exact):

    python3 /app/fit_spectra.py INPUT.csv --out OUT.json [--n N] [--prominence P]

- `INPUT.csv` — path to the two-column spectrum file.
- `--out OUT.json` — write the result JSON here.
- `--n N` (optional) — expected number of peaks; when more are detected, keep
  the N tallest and drop the rest.
- `--prominence P` (optional) — prominence threshold for peak detection; when
  omitted, derive a sensible relative threshold from the data amplitude.

Output JSON (exact schema), peaks sorted ascending by `center`:

    {"peaks": [{"center": 3.2, "width": 0.35, "amplitude": 2.5, "offset": 0.4}, ...]}

Recovered values must be close to the true peak parameters on **fresh
spectra**: centers within a small fraction of the window scale, widths and
amplitudes within tens of percent, offsets within a small absolute band. Edge
behaviours the hidden cases will probe:

- spectra with different counts of peaks, baseline levels, peak widths and
  noise levels;
- closely-spaced / partially overlapping peaks, where windows may bleed into
  neighbours (use a tolerance-consistent windowing scheme);
- a small spectrum (a few hundred points) and a spectrum whose file has a
  header row, blank lines and extra surrounding whitespace;
- peak amplitudes that differ by an order of magnitude.

**Visible run:** a fixture `/app/spectrum.csv` is provided. Run your fitter on
it and store the result **exactly at** `/app/fit_results.json` using the schema
above. The verifier re-runs your program on this file and also checks the JSON
you committed is a consistent, valid fit of that data.

## 2. Separability matrix for nested/stacked compound models — `/app/stack_models.py`

A compound numerical model has `n_inputs` inputs and `n_outputs` outputs. Its
**separability matrix** is the `n_outputs x n_inputs` binary matrix `S` where
`S[i][k] == 1` if and only if output `i` actually depends on input `k`.

You must implement the module function

    from stack_models import separability_matrix
    S = separability_matrix(model)   # -> list of lists of int (0/1)

which returns the correct separability matrix for a compound model built from
the following AstroPy pieces, **without ever sampling/evaluating the model on
numbers** and **without using `astropy.modeling.separable` or
`model.separable`/`is_separable`** — the routine must be purely structural (the
models may be black-box/symbolic, so numeric probing is not an option):

- `Linear1D(slope, intercept)` — a base 1-input/1-output affine unit with
  separability `[[1]]` (its single output depends on its single input).
- `Mapping((i0, i1, ...))` — an input permutation: output `r` reads input
  `i_r`. Its separability is the selection matrix with a single 1 per row
  (`S[r][i_r] == 1`). More than 3 outputs/inputs are possible.
- Stacking/sharing via `A & B` (concatenate a block; `A` handles the first
  `A.n_inputs` inputs, `B` the remainder, outputs are concatenated). Correct
  separability: **block diagonal** — the sub-blocks must not leak into each
  other.
- Chaining via `A | B` (feed `A`'s outputs into `B`). Correct separability:
  **boolean matrix product** of `B`'s matrix after `A`'s matrix — an output is
  coupled to an input only if an intermediate channel connects them.

The whole point: a naive "everything couples everything" compositor (for
example union-ing all inputs into every output, or treating every stacked input
as reaching every stacked output) reports separable, block-diagonal, or
permutation models as fully coupled. Your implementation must produce the
structurally correct coupling so that separable outputs stay separable. Hidden
cases will build nested/stacked compounds (blocks of blocks, chains through
permutations, stacks that include permutations, and a bare single-replacement
leaf) and compare your matrix to an independent ground truth; every `0`/`1`
must match.

Deliverables:

- `/app/stack_models.py` defines `separability_matrix(model)` as above.
- Also run your module against the **visible instrument model**

      (Linear1D(1.0, 0.0) & Linear1D(2.0, 0.0)) & Mapping((1, 0))

  and write its separability matrix to `/app/stack_result.json` with schema
  `{"inputs": N, "outputs": M, "separability": [[...]]}`. The verifier checks
  that this committed matrix matches an independent computation, and that the
  module function reproduces it and generalizes to the hidden compounds.

## 3. sqrt-Wasserstein distance — `/app/wasserstein.py`

A transport plan `P` (probability matrix, non-negative) and a per-unit cost
matrix `C` (same shape) are given as JSON arrays of arrays. The squared
transport cost is the scalar `sum_ij P[i][j] * C[i][j]`. The **actual metric
distance** is the square root of that scalar after **root-clamping to
non-negative** (a negative dot product is rounded up to 0):

    d = sqrt( max(0, sum_{i,j} P[i][j] * C[i][j]) )

Returning the **unrooted squared cost** (i.e. skipping the square root) is the
classic bug — the result is no longer a length and breaks metric comparisons
when costs are scaled. Implement and expose exactly:

    from wasserstein import sqrt_wasserstein
    d = sqrt_wasserstein(plan, cost)   # -> float, the rooted distance

plus a CLI:

    python3 /app/wasserstein.py --plan plan.json --cost cost.json [--out out.json]

- `--plan` / `--cost` — JSON files holding same-shape 2-D arrays.
- Optionally `--out out.json` writes `{"wasserstein": d}` and prints `d`.
- If `plan` and `cost` shapes differ, raise `ValueError`.
- Edge cases the hidden cases will probe: an all-zero plan (must return `0.0`),
  a plan whose dot product is negative (must return `0.0`, never `nan`),
  rectangular (non-square) matrices, and larger matrices whose expected value
  the verifier recomputes independently.

---

## General requirements

- Files must be plain, dependency-light Python that imports only numpy, scipy
  and astropy; no internet access, no /tests access.
- Program output must be exactly in the stated formats; the verifier parses
  them.
- Do not delete or rename `/app/spectrum.csv`.
- All four deliverables must be present and executable from a clean container
  when the verifier runs them on hidden inputs.
