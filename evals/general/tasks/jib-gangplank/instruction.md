# Pie chart of all-zero data crashes with a cryptic NaN error

## Situation

`/app/src` is a shallow clone of the matplotlib repository
(`https://github.com/matplotlib/matplotlib`) at an upstream commit, checked
out in detached HEAD. The library is already built and installed from that
checkout in editable mode, so `import matplotlib` resolves to
`/app/src/lib/matplotlib`, and any edit you make under `/app/src/lib` is live
immediately — no rebuild, no reinstall step.

The environment has no guaranteed network: do not attempt downloads, `git
fetch`, `curl` or `pip install` — nothing is missing, everything you need is
already installed and prebuilt.

The project's unit tests live under `/app/src/lib/matplotlib/tests` and run
with pytest. Only run targeted tests: some modules in the suite contain slow,
flaky image-comparison tests.

## The bug

matplotlib's pie chart function — `Axes.pie`, also reachable as `plt.pie` —
draws a circular "pie" of wedges whose angular sizes are proportional to a
list of numbers. The feature is widely documented and mostly works fine.

But there is one input that produces a baffling crash instead of any usable
result. If **every** wedge size passed in is zero — for example two empty
slices, or a whole series of empty slices — the chart looks like it should be
rejected with a clear error message telling the user that the data is
meaningless (there is nothing to draw). Instead, the call dies deep inside
matplotlib's internal drawing machinery with an error that has nothing to do
with pie charts:

```
ValueError: cannot convert float NaN to integer
```

The number goes to zero, the math inside the pie layout divides by it, the
angles become "not a number", and the error only surfaces later, in code that
turns angles into curved paths — far away from the pie logic and without any
mention of pie charts, wedges, or the input data. A user who hands a pie
chart all-zero data has no way to learn that the problem is their input, and
the traceback points at internal drawing code, not at the pie call.

## What you need to do

Work in the checked-out tree at `/app/src`, and deliver two things.

### 1. Write a failing reproduction first (`/app/reproduce.py`)

Before you change anything, write a self-contained Python script at
`/app/reproduce.py` that demonstrates the bug against the current tree. It
must satisfy this exact contract:

- It is run as `python3 /app/reproduce.py` and needs no arguments.
- It calls matplotlib's pie chart function with **at least one input in which
  every wedge size is zero** (e.g. two or more zero slices).
- The script encodes the *correct* behaviour as: the pie call must raise a
  `ValueError` whose message contains the text `All wedge sizes are zero`.
  When that happens, it prints a line containing exactly `REPRO-OK` and
  exits with status 0.
- In **any** other outcome — the call succeeds without raising, or raises a
  different exception, or fails with a different message — the script prints
  what actually happened (the observed error/traceback) and exits with a
  nonzero status.
- It must not read anything under `/tests`, `/solution` or `/opt`, and must
  not inspect git state; it demonstrates the behaviour purely through the
  public matplotlib API.

Run it against the current tree: it must fail — the pie call crashes with the
NaN error and there is no `REPRO-OK`. That failing run is your proof that the
bug is present.

### 2. Fix the library so the behaviour is correct

Fix the code in the checked-out tree at `/app/src` so that an all-zero
wedge-size input is rejected up front with a clear, user-facing
`ValueError` whose message contains `All wedge sizes are zero` — instead of
dying later with `cannot convert float NaN to integer`. After your fix:

- `python3 /app/reproduce.py` exits 0 and prints `REPRO-OK`;
- a pie chart of normal non-zero data still draws exactly as before
  (`ax.pie([15, 30, 45, 10])` etc. keeps working);
- the project's own existing pie tests still pass, for example:

  ```
  cd /app/src && python3 -m pytest \
    lib/matplotlib/tests/test_axes.py::test_pie_textprops \
    lib/matplotlib/tests/test_axes.py::test_pie_get_negative_values \
    lib/matplotlib/tests/test_axes.py::test_pie_invalid_explode \
    lib/matplotlib/tests/test_axes.py::test_pie_invalid_labels \
    lib/matplotlib/tests/test_axes.py::test_pie_invalid_radius \
    lib/matplotlib/tests/test_axes.py::test_normalize_kwarg_pie \
    lib/matplotlib/tests/test_axes.py::test_pie_hatch_single \
    lib/matplotlib/tests/test_axes.py::test_pie_hatch_multi \
    lib/matplotlib/tests/test_axes.py::test_pie_non_finite_values \
    -q
  ```

  (Pick the node ids you consider relevant — the point is to exercise the
  project's own tests, not to invent new ones. Keep runs targeted.)

## Constraints

- Do not change the git metadata of the checkout: no new commits, no
  rebasing, no fetching, no `git checkout` of other revisions. The tree must
  remain the same clone of the same revision, with only the code fix applied
  to your working tree. Do not add, delete or rename files inside the
  repository (the fix itself, and any scratch data, must live in the working
  tree or at `/app`).
- Everything under `/tests`, `/solution` and `/opt` belongs to the verifier;
  do not read or modify it.
- The deliverables are the repaired repository at `/app/src` and the
  reproduction script at `/app/reproduce.py`.

## What the verifier checks

1. Tree provenance: still at the pinned commit, the upstream fix commit is
   not reachable from the clone, and the only tracked change is your code fix
   (plus nothing new inside the repository).
2. Your own reproduction is executed twice: once against the pre-fix version
   of the code (it must exit nonzero and report the NaN symptom) and once
   against your repaired tree (it must exit 0 and print `REPRO-OK`) — so a
   reproduction that does not actually reproduce anything fails.
3. The project's own regression test for this behaviour, and the existing pie
   tests listed above, run against your repaired tree and pass.
4. Additional hidden cases exercise the same code path with all-zero inputs
   of shapes and keyword arguments the regression test does not use.