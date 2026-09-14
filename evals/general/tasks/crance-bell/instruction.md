# Fix the zero p-value report in `stats.wilcoxon`

## Environment

- A shallow git checkout of a real scientific-computing library (the SciPy
  source tree) is at `/app/src`. The checkout has been built and installed
  in editable mode: `import` of the library's modules resolves to the files
  under `/app/src`, and edits you make to **pure-Python** library files are
  picked up immediately, with no rebuild step, no compilation and no
  re-installation. Do not attempt to rebuild or reinstall the package; it is
  already live.
- The trial runs on a single CPU; all numeric thread pools are pinned to one
  thread already. Everything you need (compiled extensions, dependencies,
  `pytest`) is already installed in the image: you should not need to fetch
  or install anything.
- The checkout is a git repository with exactly one commit, preserved as-is.
  You may edit library source files inside `/app/src`, but you must not
  delete anything, must not add or commit commits to the repository's history,
  and must not modify anything outside the library package itself (for
  example test files must stay untouched).
- `numpy` is installed; the test runner `pytest` is installed.

## Symptom

Users have noticed that for **strongly one-sided samples** (samples where
nearly every observation sits on one side of zero), the two-sample rank test
`stats.wilcoxon(x, method='exact')` reports a p-value of exactly `0.0`, even
though the true probability is small but definitely non-zero (on the order of
1e-17). A p-value of exactly zero normally means the event is *impossible*,
which for a merely extremely unlikely sample is wrong and misleading. For
samples of the same size that are not strongly one-sided the function's
p-values look fine, and for strongly one-sided samples the *two-sided* and
*asymptotic* p-values are fine as well. Only the exact method collapses to
a flat zero.

The affected behaviour is easy to demonstrate: build a sample of a few dozen
to a hundred numbers, almost all positive but with a small number of
negatives, run `stats.wilcoxon(x, method='exact')`, and observe that
`result.pvalue` is `0.0` exactly, whereas the genuinely correct value is
tiny but strictly positive.

## Your task

1. **First, write the reproduction** at `/app/reproduce.py`: a standalone
   Python script (importable and runnable with `python3 /app/reproduce.py`)
   that demonstrates this bug against the current state of the tree.
   The script must:
   - construct its own strongly one-sided sample (do not read any sample
     from a file);
   - call the affected function with the affected options;
   - assert that the returned p-value is strictly greater than zero and, for
     good measure, that it is not pathologically far from an independent
     estimate of the probability;
   - **exit 0 if and only if** the p-value is correct (i.e. strictly positive
     and plausibly sized), and exit non-zero otherwise. In other words, while
     the bug is present the script must *fail*; after the bug is fixed the
     same script must *pass* without modification.
   Use `assert` statements plus a suitable error message, or `sys.exit`.
2. **Then fix the bug** in the library source under `/app/src` so that your
   `/app/reproduce.py` passes, and the p-value is no longer reported as
   exactly zero for strongly one-sided samples. The fix must live in the
   library's own source code in the checkout (not in `/app/reproduce.py`,
   not in a wrapper, not in an environment variable).
3. Verify your work with the library's own test infrastructure: the existing
   test class for this function must still pass in full, and your reproduction
   must pass.

## Deliverables and acceptance

- `/app/reproduce.py` — your own reproduction script, present and runnable,
  that fails on the unfixed tree and passes on the fixed tree.
- `/app/src` — the checkout, with the bug fixed in its source code, and with
  nothing outside the library package modified.

The verifier will run your reproduction against the fixed tree, check that
reverting your source change makes your reproduction fail again, run the
project's own regression test for this exact bug, run additional hidden
inputs exercising the same behaviour, and run the project's own existing
tests for the affected function to confirm nothing else broke.

Hints: start from the symptom and write the reproduction first; observe the
failure, then trace the exact-method code path that produces the p-value.
Whatever you change, the p-value must come out strictly positive *and*
close to the true (tiny) probability — a change that merely returns some
nonzero number will not pass the acceptance checks.