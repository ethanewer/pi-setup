# rudder-main

You are working inside a real open-source codebase: the Python statistical
modeling library **statsmodels**, checked out at a pinned historical commit in
`/app/src` (the working tree starts clean and already built/installed). There
is a bug in this tree's regression fitting machinery. Your job is to find it,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which module or function to change:
localising the bug is part of the task, and you must write your own failing
reproduction before you change anything.

## Environment

- statsmodels is installed from `/app/src` (editable install; the compiled
  extension modules are already built into `/app/src/build`). Importing the
  package resolves the source files straight from `/app/src`, so edits to the
  plain-Python sources take effect on the next interpreter run — no rebuild
  step is needed.
- Python 3.12 with pinned numpy, scipy, pandas, patsy, formulaic, pytest.
  `cpus = 1` (one vCPU); thread pools are pinned accordingly.
- There is **no guaranteed network** in this container. Everything needed is
  already on disk. Do not attempt to download anything.
- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, pull, rebase or otherwise modify `.git`** — the working tree is
  detached at the pinned commit and must stay there for grading.
- The project's own test suite runs with plain `pytest` from `/app/src`, e.g.
  `python -m pytest statsmodels/regression/tests/test_regression.py -q`.
  All tests use only in-memory/self-contained data and never touch the
  network.

## The bug (user-visible symptom)

`statsmodels.regression.linear_model` fits ordinary least squares (`OLS`) and
weighted least squares (`WLS`) regressions, and every fitted result carries a
`scale` attribute: the estimate of the residual variance used by the
covariance of the parameters. When a user runs a fit with a **fixed scale** —
a feature for supplying a known, pre-specified variance instead of letting the
package estimate it — the fitted result must report exactly that supplied
value in its `scale` attribute, and the "Pearson" residuals (residuals
normalised to unit variance, exposed as `resid_pearson`) must be divided by
the square root of that supplied value.

On this tree that contract is broken. If you fit `OLS` (or `WLS`) with a
user-supplied fixed scale, then:

- the result's `scale` attribute comes back roughly equal to what the package
  *would have estimated* from the residuals (about 1 for standardised data),
  **not** the value you supplied; and
- consequently `resid_pearson` is computed with the square root of that wrong
  estimate, so the normalised residuals are off by that factor too.

The parameter covariance is not affected — only the reported scale and the
normalised residuals. The affected behaviour: after a fixed-scale fit, the
result object must expose the scale the user supplied and normalise the
Pearson residuals with it. The defect is reachable whether the fixed scale is
requested through the `"fixed scale"` or the `"fixed_scale"` spelling, and
whether the fit itself is configured with it or a fitted result is
re-processed to request it afterwards. Read the code to understand *where*
the supplied value is used and *where* the result's scale still gets
recomputed from the residuals instead.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.py` — your own minimal reproduction of the symptom
   above. Its contract:

   - It uses only NumPy-random synthetic data (an explicit seed) plus the
     library; no files, no network.
   - It inserts the repository path at the head of `sys.path` for its
     imports: `sys.path.insert(0, os.environ.get("STATSMODELS_TREE",
     "/app/src"))`. It then verifies that the imported regression module
     actually resolves inside that directory; if not, it prints a message and
     exits non-zero (this prevents the reproduction from silently running
     against some other copy of the library).
   - It fits at least an `OLS` regression with a user-supplied fixed scale
     (e.g. `scale = 5.0`), then asserts the two observable facts from the
     symptom: the result's `scale` attribute equals the supplied value, and
     its `resid_pearson` equals the residuals divided by the square root of
     the supplied value. It should also exercise at least one more
     fixed-scale variant (a `WLS` fit, and/or re-processing an already
     fitted result with a fixed scale) and assert the same two facts there.
   - It prints whatever diagnostic values it used (the observed `scale`
     attribute vs the supplied value, etc.) and, on success, a final line
     `REPRO OK`. It exits 0 if and only if every assertion held.
   - It must work no matter what the current working directory is when it is
     invoked, and it must not touch anything outside `/tmp`.

   On the **unfixed** tree this script must fail: the observed `scale`
   attribute will differ from the supplied value, so an assertion raises and
   the exit code is non-zero. Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that `/app/repro.py`
   passes and the project's own regression tests stay green. Fix the general
   defect, not just one input: the same broken behaviour occurs with any
   supplied scale value, both spellings of the option, for `OLS` and `WLS`
   alike, and when a fixed scale is applied to an already fitted result (see
   Grading). Do not merely special-case your reproduction: the graded checks
   drive the code path directly, and the verifier will require the observed
   scale attribute to match whatever value *it* supplies.

3. **Break nothing else.** Everything else must keep working exactly as
   before: ordinary fits without a fixed scale must still report their
   estimated scale exactly as they did, and the whole existing regression
   test module must stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; delete any scratch files you create;
   make no commits; do not modify any test file or configuration file. The
   grader compares every file's bytes against the pinned commit's blobs, so
   cosmetic side-changes also fail. Your two authored files `/app/repro.py`
   and `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with a quick script in `/tmp` (scratch files in `/tmp`,
   never inside `/app/src`): fit an `OLS` with e.g. `scale = 5.0`, print the
   result's `scale` attribute, and observe the wrong value. Try the sibling
   variants (`WLS`, the other spelling, re-processing an already fitted
   result) to pin down the exact reachable surface.
2. **Localise** the bug by reading the source. Follow where the supplied
   scale is consumed and where the result's `scale` attribute is produced for
   each fit type; understand why the result still reports the residual-based
   estimate even though the supplied value was used for the covariance.
3. Write `/app/repro.py` per the contract, and confirm it **fails** on the
   unfixed tree.
4. **Fix** the smallest possible defect, re-run `/app/repro.py` (now it must
   print `REPRO OK` and exit 0), and re-run the exact same repro against a
   fit that does **not** supply a fixed scale to confirm nothing else moved.
5. **Prove nothing else broke**: run the project's own regression test module
   with `python -m pytest statsmodels/regression/tests/test_regression.py -q`
   and require it fully green.
6. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.py` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream fix
  commit is **not** reachable from this clone, and that every tracked file
  except the single source file your fix lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.py` and `/app/summary.md` to exist and be non-empty,
  run `/app/repro.py` against the repaired tree (must exit 0 and print
  `REPRO OK`) **and** against the pristine pre-fix module baked into the
  image at `/opt/prefix` (must fail — proving the symptom is real and your
  reproduction targets it);
- additionally verify the symptom directly: fitting with a fixed scale must
  report the supplied scale, on the pre-fix module it must not;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree), run it, and require it to pass;
- run the whole project test module `statsmodels/regression/tests/
  test_regression.py` and require it to stay green (the planted test raises
  the pass count from 369 to 370);
- run authored hidden cases exercising the same code path from inputs the
  upstream regression test does not use: other supplied scale values, other
  data shapes and seeds, a `WLS` fit, re-processing an already fitted
  result, and `use_t = True` — each asserted against an independent NumPy
  computation of the expected scale and normalised residuals.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.