# saffron-dial — reef survey diversity library

A marine-monitoring consultancy consumes your R library through a fixed
plug-in contract: it scans the **source text** of your script for two entry
points at the start of a line, then loads the file and calls those functions on
its own hidden survey data. Both the naming and the numerics are enforced.

## Deliverables

1. `/app/diversity.R` — an R source file that defines (at minimum) the two
   required functions, spelled exactly like this, each **at the start of a
   line** (the consumer finds them with a line-anchored regex, so leading
   whitespace or a different name/case makes the plug-in discovery fail):

   ```r
   reef_diversity(counts, base = 2)
   reef_selftest()
   ```

2. `/app/selftest.log` — the output of running your self-test:

   ```
   cd /app && Rscript -e 'source("/app/diversity.R"); reef_selftest()' > /app/selftest.log 2>&1
   ```

   The log must exist, be non-empty, and contain the token `PASS`.

## Function contract

### `reef_diversity(counts, base = 2)`

Computes the Shannon diversity index of an abundance vector:

- `counts` is a numeric vector of abundances: all values finite and `>= 0`.
  Zero entries are ignored; the probabilities are `p_i = counts_i / sum(counts)`
  over the strictly positive entries.
- The index is `H = -sum_i p_i * ln(p_i) / ln(base)`, so `base` selects the log
  base: `2` gives bits, `exp(1)` gives nats, `10` gives dits, any other
  positive value scales accordingly. `base` may be given positionally or by
  name and must default to `2` when omitted.
- Edge cases (all probed by hidden data):
  - a length-0 vector returns `0`;
  - an all-zero vector returns `0`;
  - a single positive species returns `0`;
  - zero entries must not contribute and must not produce NaN;
  - fractional (double) abundances are allowed.
- Invalid input must be rejected with `stop(...)` (the consumer relies on a
  non-zero R error status, never a silent NaN):
  - any negative, `NA`, `NaN`, or infinite abundance;
  - `base <= 0` or `base == 1`;
  - a non-numeric `counts`.

### `reef_selftest()`

A self-test routine that:

- calls `reef_diversity` on several fixed checks and compares against
  analytically known values, e.g. `c(1,1)` -> `1` (bit), `c(3,3,3,3)` -> `2`,
  `c(5)` -> `0`, an all-zero vector -> `0`, and one `base = exp(1)` case;
- prints one line per check, each containing either `PASS` or `FAIL`, and a
  final line containing `SELFTEST PASS` on success;
- returns exit status `0` when every check passes; if any check fails it
  prints a line containing `FAIL` and exits non-zero (e.g. via `quit(status=1)`).

## What the consumer (grader) does

- Reg-ex scans `/app/diversity.R` and requires both required names at the start
  of a line (exact spelling and case; a renamed, re-cased, or indented
  definition fails discovery).
- Fresh-loads `/app/diversity.R` in its own R process and calls
  `reef_diversity` on hidden survey vectors (varied bases, zeros, single
  species, fractional abundances, an empty vector), comparing your returned
  value to its own independently computed reference to within `1e-6`.
- Feeds invalid inputs (a negative abundance, `base = 1`, `base = 0`) and
  requires the call to raise an R error (non-zero exit), not return a value.
- Re-runs `reef_selftest()` itself, requiring exit status `0` and a `PASS`
  line in the output.
- Checks `/app/selftest.log` exists, is non-empty, and contains `PASS`.

## Constraints

- Work only inside `/app`. Base R only — no external packages.
- Deterministic: no randomness is needed anywhere.
- Do not wrap the required definitions inside another function or a `if`
  branch; they must be top-level definitions at line start.
