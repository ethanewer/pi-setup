# basalt-quill — spectral fitting, model separability, CEM, and rejection sampling

You are given a workspace `/app` on a Python 3.12 image with `numpy`,
`scipy`, `astropy`, `sympy`, and an R runtime (`Rscript`). Four small,
independent scientific-computing jobs share this workspace. **Build all four.**
Each produces one or more real files at the exact paths below. The verifier
re-runs your programs on its own hidden inputs (see "How you are graded"),
so your code must be a working program, not a one-shot answer.

Executable programs you write must be runnable as CLI tools as documented.
Do not modify the shipped fixtures `/app/spectrum.csv` and
`/app/spec_default.json`; they are the inputs that `/app/fit_results.json`
and `/app/separability.json` must be the outputs of.

---

## 1. Lorentzian spectral fitting -> `/app/fit_spectra.py` (+ `/app/fit_results.json`)

`fit_spectra.py` is a CLI that crops each peak's local window in a spectrum and
fits a lorentzian profile.

**Interface (exact):**

```
python3 /app/fit_spectra.py <input.csv> -o <out.json>
```

- `input.csv` has a header line `wavelength,intensity`, then pairs of numbers.
  `wavelength` is strictly increasing.
- **Model**: one peak is
  `y(x) = offset + amplitude * width^2 / ((x - center)^2 + width^2)`.
  `width` is the half width at half maximum, `amplitude` is the peak height
  above the baseline, `offset` is the constant baseline.
- You must *detect* the peaks (a global fit over the whole spectrum is not
  enough when several peaks are present), *crop each peak to its own local
  window*, and fit via a curve-fit routine with sensible starting values
  (e.g. `scipy.optimize.curve_fit`).
- **Output JSON**: `{"peaks": [ {"center": float, "width": float,
  "amplitude": float, "offset": float}, ... ]}` with peaks sorted by
  `center`.

**Required behaviour / edge cases the verifier will probe:**

- Multi-peak spectra: the number of detected peaks must match the number of
  actual peaks, and each peak's recovered parameters must be close to the true
  ones (see tolerances below).
- A constant or near-flat spectrum must yield `{"peaks": []}` (no peaks).
- An empty input (just a header, or no data rows) must yield `{"peaks": []}`
  and exit 0. If fewer than 3 data rows exist, yield `{"peaks": []}`.
- Peak detection must use a non-trivial *prominence* so that tiny noise
  wiggles are not reported as peaks; treat a peak as real only when its local
  prominence is a meaningful fraction (about 5%) of the spectrum's range.
  Baseline is constant across the spectrum in all our data.

**Reference tolerances** (a correct fit passes comfortably; a wrong model —
e.g. a Gaussian, or missing the offset — fails): recovered vs. reference
`|center| <= 0.8`, `|width/w_ref - 1| <= 0.12`, `|amplitude/a_ref - 1| <= 0.12`,
`|offset - o_ref| <= 0.20`.

**`/app/fit_results.json`**: produce it by running

```
python3 /app/fit_spectra.py /app/spectrum.csv -o /app/fit_results.json
```

---

## 2. Separability matrix for compound astropy models -> `/app/stack_models.py` (+ `/app/separability.json`)

`stack_models.py` builds nested / stacked / blocked astropy `CompoundModel`
expressions from a JSON spec and computes each model's **separability matrix**
— the correct one for nested & multi-input stacked models, not an
over-coupled naive composition.

**Interface (exact):**

```
python3 /app/stack_models.py <spec.json> -o <out.json>
```

`spec.json` is a serialized expression tree:
- `{"op":"cat","a":EXPR,"b":EXPR}` — block-concatenate the two submodels.
- `{"op":"pipe","a":EXPR,"b":EXPR}` — stack them (apply `a`, then `b`; note
  the keys may also be `"left"`/`"right"`).
- leaf `{"leaf":...}`:
  - `{"leaf":"shift","offset":F}` (1<->1)
  - `{"leaf":"scale","factor":F}` (1<->1)
  - `{"leaf":"linear","slope":F,"intercept":F}` (1<->1)
  - `{"leaf":"mapping","n_in":I,"index":[ints]}` (I inputs, len(index) outputs;
    output k is a copy of input `index[k]`)
  - `{"leaf":"poly2d","degree":I,"coeffs":{"c0_0":F,...}}` (2 inputs -> 1 output)
  - `{"leaf":"rotation","angle":F}` (2<->2, non-separable)

You MUST emit the astropy compound model using `&` for `cat` and `|` for
`pipe` on these primitives (`astropy.modeling.models` + `Mapping`).

**Separability matrix**: shape **(n_outputs x n_inputs)**, entry `(i,j) == 1`
iff output `i` analytically depends on input `j` (all-zeros for a constant).
The correct value for a compound is obtained by composing each piece's
coordinate-transform matrix in the order the models run (intra `cat` is a
block-diagonal concat; `pipe` is a matrix product). **This is the genuinely
subtle part.** A naive recipe that, e.g., treats every `cat` as a plain
diagonal, or that chains input indices without honoring where a nested
multi-input submodel's outputs feed the next stage's inputs, produces an
over-coupled (all-ones) or permuted matrix that the verifier rejects.

You must **implement** this composing procedure yourself inside
`stack_models.py` and make it return the same matrix astropy computes
(`astropy.modeling.separable.separability_matrix(model)`). Do **not** just
delegate to that function — implement the coordinate-transform composition
yourself in `stack_models.py` (you may use astropy to build models and to
validate offline, never to compute the return of the CLI).

**Output JSON**: `{"n_inputs": int, "n_outputs": int, "matrix": [[0/1 ...], ...]}`,
`matrix` shape `n_outputs x n_inputs`.

**`/app/separability.json`**: produce it by running

```
python3 /app/stack_models.py /app/spec_default.json -o /app/separability.json
```

---

## 3. Cross-entropy optimizer with shared-prefix memoization -> `/app/cross_entropy_opt.py`

The file implements (a) a given reward/scores over fixed-length discrete
sequences, (b) a **cross-entropy optimizer** that updates an action-probability
tensor (preserving its shape) and improves, and (c) a **memoised scorer** whose
caches shared-prefix computations and is faster on overlapping batches.

**Reward (must match exactly).** Sequences are integer actions `seq` of length
`L` over `K` symbols. Given tables `W[L][K]`, `BP[L][L+1]`, `XC[L][K]`:

```
freq = [0]*K
value = 0.0
for i in 0..L-1:
    a = int(seq[i]); freq[a] += 1
    value += W[i][a]
    if freq[a] > 1: value += BP[i][freq[a]]
    value += float(sum(XC[i][j]*freq[j] for j in 0..K-1))   # coupling term
score(seq) = value
```

**CLI subcommands:**

```
python3 /app/cross_entropy_opt.py optimize --spec <spec.json> -o <out.json>
python3 /app/cross_entropy_opt.py memo     --spec <spec.json> -o <out.json>
```

`optimize` input spec: `{"K":int,"L":int,"W":[[...]],"BP":[[...]],"XC":[[...]],
"theta0":[[...]],"n_iterations":int,"n_samples":int,"seed":int}`. It must run
`n_iterations` generations of: sample `n_samples` sequences from the current
product distribution; score them; take a fixed top fraction as the **elite**;
re-estimate each row's `theta` as a smoothed empirical distribution over the
elite (all probabilities > 0, each row sums to 1). **Output**:
`{"rows":int,"cols":int,"final_theta":[[...]],"history":[...],"improvement":float}` where
`final_theta`.shape == `theta0`.shape, rows sum to 1, entries non-negative, and
`improvement = history[-1] - history[0]`.

`memo` input spec: same `W`, `BP`, `XC` tables as `optimize` plus
`"sequences":[[ints...]]`. It must return the exact per-sequence score (the
"memoized" value equals the direct recomputation of the reward above for every
sequence to floating-point round-off) and must be **faster than the direct
non-memoized recomputation** on strongly overlapping batches. The verifier
checks: (a) your `scores` equal an independent direct recomputation of the
reward formula (`<= 1e-6`); (b) `speedup = brute_time / memo_time > 2.0` on a
hidden batch with heavy shared prefix structure; (c) the count of scores is
the number of sequences.

Implement a real shared-prefix memo (an explicit cache keyed on overlapped
prefixes, handling sequences passed as numpy arrays) — not a graph-of-just
reusing the full-string, which does not scale to heavy overlap. Input
`sequences` may be numpy arrays; handle hashed numpy keys.

---

## 4. Adaptive rejection sampling in R -> `/app/ars.R` (+ `/app/sample.csv`)

`ars.R` must define a single function:

```r
ars <- function(logf, lo, hi, n, init = NULL, seed = 1)
```

which draws `n` samples from the (unnormalized) density proportional to
`exp(logf(x))` for a **log-concave** target on the finite domain `[lo, hi]`,
using **adaptive rejection sampling** (an incremental piecewise-exponential
upper hull of the tangent lines of `logf`, sampling from the envelope and
accepting/rejecting against `exp(logf)`, adding rejected interior points to the
support). Return a real vector of length `n`, all finite, whose empirical
distribution reproduces the target (correct empirical mean and standard
deviation).

The verifier `source()`s your file and calls `ars()` on several hidden
log-concave targets (e.g. ~ N(0,1) and a ~Gamma-shaped density over a bounded
domain) and checks counts, finiteness, and that the empirical mean and sd are
close to the reference (< ~0.1). A sampler that returns, e.g., near-uniform
points, fails those statistics.

**`/app/sample.csv`**: a CSV with a header `value` and 2000 numeric rows,
produced by running your `ars()` (e.g. for N(0,1)):
`Rscript --vanilla -e "source('ars.R'); s <- ars(function(x)-0.5*x^2,-8,8,2000,seed=1); write.csv(data.frame(value=s),'sample.csv',row.names=FALSE)"`.
The row is the deliverable file `/app/sample.csv` at least 1000 rows.

---

## Deliverable summary (exact paths)

| path | produced by |
|------|------|
| `/app/fit_spectra.py` | your program |
| `/app/fit_results.json` | run fit_spectra.py on `/app/spectrum.csv` |
| `/app/stack_models.py` | your program |
| `/app/separability.json` | run stack_models.py on `/app/spec_default.json` |
| `/app/cross_entropy_opt.py` | your program |
| `/app/ars.R` | your program |
| `/app/sample.csv` | run ars.R |

Do not leave any created file with mode 000 / unreadable; do not create files
elsewhere that change `/app/spectrum.csv` or `/app/spec_default.json`.

## How you will be graded

After you stop, a verifier runs **your** programs on fresh hidden inputs and
checks exactness against independent references:

1. `fit_spectra.py` on hidden spectra (single-peak, two-peak, zero-offset,
   constant, and empty/malformed) — counts + the tolerances in §1.
2. `stack_models.py` on hidden `spec.json` trees, comparing your returned
   `matrix` entry-for-entry with the astropy-computed ground truth.
3. `cross_entropy_opt.py` on hidden `optimize` and `memo` specs — shape /
   convergence / exactness vs direct recompute / memo `speedup > 2`.
4. `source('/app/ars.R')` + `ars()` on hidden log-concave densities — counts,
   finiteness, empirical moments; plus basic checks of `/app/sample.csv`.

Reward is 1 only if all of the above pass. Build everything from scratch for
**this** environment; no internet at run time (line packages are installed).