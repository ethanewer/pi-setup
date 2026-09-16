# Task: repair a nonsensical trial budget in scikit-image's robust fitting

## Environment

- Python 3.12 with the scientific stack preinstalled (numpy 2.1.3, scipy 1.14.1,
  pytest, Cython, meson). The package `scikit-image` is installed **editable**:
  the working tree at `/app/src` **is** the importable package, so an edit to a
  source file under `/app/src` takes effect immediately, with no rebuild step.
- `/app/src` is a git checkout of the upstream scikit-image repository, detached
  at a pinned historical commit. It is a shallow clone whose object store holds
  exactly that one commit: there is no other history to consult.
- You are root. There is no network access other than what is already baked in.

## Symptom

scikit-image's robust-fitting routine `ransac` (in `skimage.measure`) decides how
many random subsets to draw so that, with a given confidence, at least one drawn
subset is free of outliers. Internally it computes a maximum number of trials
from the target confidence ("stopping probability"), the inlier ratio of the
data, and the minimum number of samples per subset.

Users report that for extreme-but-legal inputs the computed maximum number of
trials can come back as **zero or a negative number**, which is meaningless as an
iteration budget. Two families of inputs trigger it:

- a stopping probability that is numerically indistinguishable from 1
  (e.g. `1e-40`), where the "probability that a trial fails" term rounds to
  exactly 1 in floating point; and
- combinations where the "probability that a single all-inlier subset is drawn"
  term also rounds to exactly 1.

The computed trial count is an integer number of attempts; it must always be a
**positive** integer (or the well-defined infinities below). A result of zero or
negative means the routine would draw no candidate models at all, silently
returning garbage rather than failing.

## Deliverables

All three deliverables are required; create them while the fix is still absent,
then repair the library, then re-run.

### 1. `/app/repro.py` — your own failing reproduction

Write a Python program that demonstrates the defect **through the installed
package** (import scikit-image; do not re-implement the budget formula yourself,
and do not hardcode expected results).

Contract:

- Probe a representative set of extreme scenarios you pick — small stopping
  probabilities (well below machine epsilon, like `1e-20` and smaller), several
  distinct `min_samples` values, and several inlier ratios — by asking the
  installed package for the maximum trial count in each.
- Print, for each probe, one line showing the inputs and the returned value, e.g.
  `probe: min_samples=3 inliers=1/100 p=1e-40 -> trials=...`.
- The program must consider the behaviour correct only when every probed count is
  a positive integer, and must record the outcome: exit code 0 if and only if all
  probes satisfy the contract; otherwise exit non-zero after printing the failing
  probes.
- Do not special-case any inputs: the same scenarios must yield a positive count
  under a correct implementation, so the program must fail when run against the
  broken library and pass when run against the repaired one.

Before fixing anything, run `/app/repro.py` against the current tree and confirm
it fails — that failing run is your reproduction of the report.

### 2. The repair, in `/app/src`

Find where the maximum-trial budget is computed inside the robust-fitting
implementation, diagnose why the current arithmetic can yield a non-positive
count for the extreme inputs above, and repair it. Keep the change minimal and
local to that computation; the existing behaviour for ordinary inputs
(same results, same precision) must be preserved.

Constraints:

- Only the single source file that contains the defect may be modified. Every
  other file in the tree must stay byte-identical to the pinned commit. Do not
  commit; do not add files to the tree.
- You are not required to reinstall or rebuild anything; the editable install
  picks up your source edit directly.
- Your reproduction must fail on the unmodified tree and pass after your repair,
  and the project's existing test suite for the robust-fitting module
  (`python3 -m pytest skimage/measure/tests/test_fit.py -p no:cacheprovider -q`)
  must still pass in full.

### 3. `/app/summary.md` — change summary

Write a markdown file (in `/app/`) covering:

- the user-visible symptom and your reproduction of it (include the failing
  output of `/app/repro.py` as captured against the broken tree);
- the root cause: why the arithmetic can produce a non-positive number of
  trials for the extreme inputs, including the floating-point rounding involved;
- the change you made, and why it is sufficient and minimal;
- how you verified the repair (outputs of your reproduction and of the existing
  test run).

## Judging

Your work is scored by an automated verifier that runs after you: it checks the
deliverables above, re-runs your reproduction against **both** a pristine
pre-repair copy of the library (where it must still fail, proving the symptom is
real and your reproduction targets it) and against your repaired tree (where it
must pass), runs the project's own regression and existing tests, and runs
additional hidden probes of extreme inputs you never saw. Nothing is scored
except what the verifier can observe: the deliverables, the repaired tree, and
the behaviours above.