# Sable Quill — estuarine gauge Monte-Carlo module

The *Sable Quill* estuarine survey team ships a small R module for the
salinity gauge's calibration report. You must author the module
**`/app/tidekit.R`** and the recorded self-test log **`/app/selftest.log`**.
An independent grader re-loads the module in a fresh R process and
exercises it, so the module must be a real, general implementation — not a
hard-coded answer.

## Deliverables (both required)

1. `/app/tidekit.R` — an R source file defining **exactly two obliged
   functions**, spelled exactly, defined at **column 0** (the grader
   regular-expression-checks the source for the definitions at line start):

   ```
   tide_estimate(n, rate = 0.4)
   tide_selftest()
   ```

2. `/app/selftest.log` — the output of running the module's self-test:

   ```
   cd /app && Rscript -e 'source("/app/tidekit.R"); tide_selftest()' > /app/selftest.log 2>&1
   ```

   It must exist, be non-empty, and contain the token `PASS`.

## Function contracts

### `tide_estimate(n, rate = 0.4)`

- Draws `n` variates from the exponential distribution with rate `rate`
  using `stats::rexp` — i.e. call it namespaced, `stats::rexp(n, rate = rate)`
  — and returns their arithmetic **mean** as a single finite numeric (a
  Monte-Carlo estimate of the expectation `1/rate`).
- The function must **seed R's RNG inside the function body** (e.g.
  `set.seed(<a fixed integer of your choosing>)`) so two calls with the
  same arguments return **identical** values (the grader checks
  reproducibility by calling it twice and comparing).
- `n = 1` must return a finite number.
- `n < 1` (including 0 and negatives), or a non-numeric / `NA` / non-scalar
  `n`, must raise an R **error** (`stop(...)`) — never return `NA`, `NaN`,
  `-Inf` or silently misbehave. A non-positive / non-numeric `rate` must
  also raise an error.

### `tide_selftest()`

- Calls `tide_estimate` (a large `n` of your choosing with the default
  rate), compares the estimate against the exact expectation `1/rate`
  within a tolerance you state in the code, and:
  - on success prints a line containing the token `PASS` and exits with
    status 0;
  - on an out-of-tolerance estimate prints a line containing `FAIL` and
    exits with a **non-zero** status.

## How the grader checks it

- Both obliged names must appear **at line start** in `/app/tidekit.R`
  (definitions like `tide_estimate <- function(...)` at column 0; a
  renamed, re-cased, or indented definition fails the regex).
- It sources the module and runs `tide_estimate` on fresh hidden
  `(n, rate)` combinations — including `n = 1` — requiring a finite value
  close to `1/rate` within the documented tolerance, plus one case where
  `n = 0` must raise an error.
- It re-runs `tide_selftest()` itself and requires exit status 0 and a
  `PASS` line on stdout.
- It checks reproducibility (two identical calls agree exactly).

## Constraints

- Work only inside `/app`. Standard R (base + stats) only; no extra
  packages, no network.
- The grader runs the module in a **fresh R process**, so do not depend on
  any state in your interactive session.
