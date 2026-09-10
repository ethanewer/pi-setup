# jib-tarn: hunt a performance regression in a shipped repository

You are handed a real git repository at `/app/repo` (branch `main`, 25
commits) implementing **sundial**, a small pure-Python library for windowed
analytics over event series: sliding-window maxima, spike (outlier) detection
over window maxima, descriptive statistics, a CSV persistence layer, a small
CLI and a benchmark harness. The repository is fully built: `python3 -m
pytest -q` passes, and the benchmark harness runs.

It is not healthy, though. Somewhere between the first and the last commit a
**performance regression** was introduced into one of the library's hot
execution paths, and it is present at the tip of `main`: the code is correct
(every test passes) but a core operation that used to scale linearly with the
input size now scales quadratically. The regression is *not* in the test
suite and *not* in the benchmark harness itself — those are fine.

Your job has three parts.

## 1. Reproduce and locate the regression

- Run the shipped benchmark harness:

  ```
  cd /app/repo
  python3 benchmarks/bench.py
  ```

  It prints the median wall time of the library's hot operation at input
  sizes 2000, 4000, 8000 and 16000 (window = half the input size). A healthy
  implementation shows times growing roughly linearly with `n`; the current
  tip shows roughly quadratic growth.
- Identify the commit that introduced the regression. `git bisect` is the
  intended tool — mark the current tip `bad`, mark an early commit `good`,
  and use the benchmark harness (or a small timing probe of your own) to
  classify every intermediate point. You may use any equivalent fault
  localization you prefer, as long as you end with the fix.

## 2. Fix the regression

Restore linear-time behaviour for the hot operation at the harness's sizes —
"doubling the input doubles the runtime", not quadruples it. Keep the change
surgical:

- Do not change any public function name, signature, return type or module
  layout; the public API must remain import-compatible (`import sundial`,
  `import sundial.window`, `import sundial.io`, ... must keep working).
- Do not delete, rename or rewrite any shipped test; the shipped correctness
  suite must stay exactly as green (and as numerous) as it is now.
- All shipped modules and files must remain present under `/app/repo`.
- Do not cache results keyed on input content, do not special-case sizes or
  data patterns, and do not fake timings: the fix must be a real algorithmic
  fix that is correct for arbitrary input.

## 3. Make the benchmark part of the suite

Add a **benchmark regression test** under `/app/repo/tests/` (any
`test_*.py` filename) that measures the hot operation at increasing input
sizes and fails the suite when the operation is (re-)quadratic. The verifier
will re-introduce the regression in a scratch copy of your repository and
re-run the suite there, so your test must actually be sensitive. Concretely
it must:

- pass on your fixed repository (as part of `python3 -m pytest -q`),
- **fail** when the regression is re-introduced (the scratch-copy check),
- finish in roughly 45 seconds or less even in that failing case (no
  runaway timings),
- never be skipped, xfailed or otherwise neutered — a timing-free trivially
  passing test costs the whole task.

A robust way to write it is a **scaling check**: time the operation at two
(or three) input sizes that double, and assert the runtime grows well below
4x (a linear implementation is ~2x; a quadratic one is ~4x). Use medians or
minima of several runs and generous thresholds so a normally loaded single
CPU does not produce false alarms. Before you finish, prove (b) to yourself:
make a throwaway clone of `/app/repo`, re-introduce the regression
(e.g. `git revert` your fix there, or recover the offending commit's version
of the hot module), run your new test against it, confirm it fails, then
throw the clone away. The shipped repository must not contain any such scratch
state when you are done.

## Environment

- Debian-based container, Python 3.12, `git`, `pytest 9.1.1`. No network at
  trial time; nothing may be pip-installed or downloaded. All code is
  standard library.
- Everything you need is inside `/app/repo`; there is nothing to fetch.
- Work only inside `/app/repo`. Do not modify anything else under `/app`, and
  do not modify the repository's `.git` configuration.

## Deliverables

1. **`/app/repo`** — the repository with:
   - the performance regression fixed (linear-time hot operation),
   - the benchmark regression test added under `tests/`,
   - the full suite green: `cd /app/repo && python3 -m pytest -q` exits 0,
   - the history intact: your fix may be uncommitted working-tree state or a
     new commit; either way the original 25-commit history must still be
     there.
2. **`/app/bench.json`** — written by running the harness on the **fixed**
   repository at its default sizes:

   ```
   python3 /app/repo/benchmarks/bench.py --repeats 3 --json /app/bench.json
   ```

   The file must be JSON with exactly `{"n": [2000, 4000, 8000, 16000],
   "k": [1000, 2000, 4000, 8000], "ms": [...]}` — a numeric `ms` entry per
   size — and must reflect the fixed repository (linear-ish scaling).

## How the verifier grades you

The verifier runs the suite and re-runs the harness on `/app/repo`, then
times the hot operation at **three hidden input sizes** (not the harness's
defaults) against a reference implementation that is part of the test image.
Your repository passes a hidden size when its runtime stays within a generous
factor of the reference. Finally it re-introduces the regression into a
scratch copy of your repository and requires at least one of your test files
(one that passes on the fixed repository) to fail there. Every check must
pass; there is no partial credit.