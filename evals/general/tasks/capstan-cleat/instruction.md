# Reference lines with a tiny slope are drawn exactly horizontal

## Situation

`/app/src` is a shallow, pinned clone of the matplotlib repository
(`https://github.com/matplotlib/matplotlib`) at upstream commit
`7722dead68f8de43480f1f58386d03396bd5d58e`, checked out in detached HEAD. The
library is already built and installed from that checkout in **editable**
mode, so `import matplotlib` resolves to `/app/src/lib/matplotlib`, and any
edit you make to a `.py` file under `/app/src/lib` is live for the next
Python process — no rebuild, no reinstall step. Everything needed to build
and test is baked into the image; there is **no network** at trial time:
`git fetch`, `pip install`, `curl` and any other network use will fail.

The project's unit tests live under `/app/src/lib/matplotlib/tests` and run
with the project's own runner:

```
cd /app/src && python3 -m pytest lib/matplotlib/tests/test_lines.py -q
```

`-k <substring>` or `::<testname>` selects individual tests. Only run
targeted tests: some modules in the suite contain slow, flaky
image-comparison tests that are not usable here.

## The bug

A user reports:

> I draw an infinite reference line through a point with `ax.axline(...)`,
> giving it a **very small slope**. When the slope is tiny but not zero —
> on the order of 1e-14, but also up to about 1e-9 — the line is drawn
> perfectly horizontal, as if the slope had been rounded to zero: it no
> longer follows the angle I asked for, and where it intersects other
> plotted data is visibly wrong. Any slope up to around 1e-8 is flattened;
> slopes around 1e-7 and larger are drawn correctly. If I pass a slope that
> is *exactly* 0 I do want a horizontal line — that part works and must
> keep working.

A line whose slope is small but non-zero must keep its slight tilt; only a
slope that is exactly zero may be drawn horizontal.

This is a real bug in this checkout. Your job is to fix it in `/app/src`.

## Deliverables

1. `/app/repro.sh` — an executable shell script **you author**, which
   reproduces the bug using the project's own test machinery, per the
   contract below.
2. `/app/src` — the fixed tree: the repository with the minimal source
   change that restores a slight tilt to small non-zero slopes while keeping
   any exactly-zero slope horizontal.
3. `/app/explanation.md` — a short root-cause note: what the line-drawing
   code did with a tiny slope, why that turned it into a horizontal line,
   and the minimal change you made.

## The reproduction contract

Write `/app/repro.sh` so that it:

- takes no arguments and runs entirely offline;
- drives the project's own test runner (`python3 -m pytest`) against a
  scenario test file **you write** — install a small `test_*.py` into
  `lib/matplotlib/tests/`, run your scenario with the runner, remove the
  file again, **print the test run output**, and exit with the test run's
  exit status;
- asserts the **correct** behaviour in its scenario — a small non-zero slope
  (for example `1e-14`) through the origin must produce a line whose
  transform maps two different data points to slightly different
  y-coordinates (a small but non-zero `dy`), with a slope of exactly zero
  still mapping them to the same y — so that on a checkout that still has
  the bug the run fails (the buggy line gives `dy == 0.0`), and on a fixed
  checkout it passes;
- leaves no trace: when `/app/repro.sh` finishes, the repository must not
  contain the scenario file or any other artifact of the run.

The verifier runs your reproduction **twice**: once against the pre-fix tree
(the rendering source restored to the pinned version — your reproduction must
fail there and print a failing test run), and once against your repaired tree
(it must pass and print a passing test run). A reproduction that does not go
through the project's own test runner, or that passes or fails regardless of
the tree state, scores nothing.

## How to work

- Explore `/app/src` to find where the axline geometry is computed. The
  expansion of a slope-and-point description into the actual infinite line
  is what you need to change; the fix belongs in that same file and nowhere
  else.
- Write your reproduction first, before touching any source, and confirm it
  fails on the current tree. Then fix the geometry so the reproduction — and
  the existing tests that exercise this code — pass.
- Remove scratch files before finishing: the final repository state must
  differ from the pinned commit by **the minimal source fix only**. Your
  reproduction lives at `/app/repro.sh`, outside the repository.

## Constraints

- No network; nothing may be installed or fetched.
- Do not read or modify `/opt/golden`, `/tests` or `/solution`; they are
  harness-owned.
- Do not commit, rebase, fetch or otherwise mutate the repository's history;
  `HEAD` must stay at the pinned commit and the only difference from it is
  your source fix. Do not add or delete files inside the repository.

## What the verifier checks

1. Provenance: `HEAD` is still the pinned commit; the repository state
   differs only by the minimal source fix; your reproduction exists, is
   executable, and drives the project's own test runner.
2. Your reproduction against the pre-fix tree (must fail and print a failing
   pytest run) and against your repaired tree (must pass).
3. The project's own upstream regression test for this bug (extracted at
   image build time) passes against your tree.
4. A subset of the project's own existing tests that exercise the same code
   passes, proving the fix broke nothing else.
5. Hidden cases authored for this task exercise the same code path with
   slopes and anchors the upstream test does not use.

Deliverable: the fixed `/app/src`, your authored `/app/repro.sh`, and the
root-cause note `/app/explanation.md`.