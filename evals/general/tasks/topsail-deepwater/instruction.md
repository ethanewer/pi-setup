# The TSDB dump is silently dropping the earliest samples of histogram series

## Situation

`/app/src` is a shallow, pinned clone of the Prometheus server repository
(`https://github.com/prometheus/prometheus`), checked out at upstream commit
`6f81b2271a90887048f209298382340d61f35faf`. The Go toolchain version 1.26.0 is
installed at `/opt/go/bin` and on `PATH`; the project's modules are pre-fetched
and the promtool command has been compiled once, so everything you need runs
without any network. There is **no network** at trial time: `git fetch`,
`curl` and any other network use will fail.

The repository's own command-line tool `promtool` has a TSDB dump feature that
prints every stored sample of a storage directory as one text line per sample,
`{labels...} value timestamp`. Its tests live under `cmd/promtool/` and are
run with the project's own test runner:

```
cd /app/src && go test -v ./cmd/promtool
```

`-run <substring>` filters to matching tests. Everything the runner needs is
already cached; do not add flags or try to download anything.

## The bug

A user reports:

> I stored metrics whose values are histograms, some series mixing plain
> numbers and histograms in the same series, and ran the TSDB dump. The dump
> is incomplete: the **earliest** samples of the histogram series are missing —
> sometimes the first sample of a histogram run, sometimes two or more — with
> no error and no warning. Dumping the same data twice is deterministic: the
> same samples are missing every time. When I feed the dump data that contains
> a value type it does not recognize, it keeps going and prints nothing usable
> for that sample instead of reporting the problem.

The dump looks right for series that contain only plain numbers; the losses
happen where a series switches between plain values and histograms, and all
the missing samples are early in a run of values of the same type.

This is a real bug in this checkout. Your job is to fix it in `/app/src`.

## Deliverables

1. `/app/repro.sh` — an executable shell script **you author**, which reproduces
   the bug using the project's own test machinery, per the contract below.
2. `/app/src` — the fixed tree: the repository with the minimal source change
   that makes the dump complete and correct.

## The reproduction contract

Your `/app/repro.sh` must:

- take no arguments and run entirely offline;
- drive the project's own test runner (`go test`) against a scenario test file
  **you write** — install a small `*_test.go` into `cmd/promtool/`, run your
  scenario with the runner, remove the file again, **print the test run
  output**, and exit with the test run's exit status;
- assert the **correct** behaviour in its scenario (a complete dump: every
  histogram and every plain sample present, earliest samples included), so
  that on a checkout that still has the bug the run fails, and on a fixed
  checkout it passes;
- leave no trace: when `/app/repro.sh` finishes, the repository must not
  contain the scenario file or any other artifact of the run.

The verifier runs your reproduction **twice**: once against the pre-fix tree
(the dump source restored to the pinned version — your reproduction must fail
there and print a failing test run), and once against your repaired tree (it
must pass and print a passing test run). A reproduction that does not go
through the project's own test runner, or that passes or fails regardless of
the tree state, scores nothing.

## How to work

- Explore `/app/src` to find where the TSDB dump is implemented. The dump
  rendering is what you need to change; the fix belongs in the same file the
  rendering lives in, and nowhere else.
- Write your reproduction first, before touching any source, and confirm it
  fails on the current tree. Then fix the dump logic so the reproduction — and
  every test that exercises the dump — passes.
- Remove scratch tests before finishing: the final repository state must differ
  from the pinned commit by **the minimal source fix only**. Your reproduction
  lives at `/app/repro.sh`, outside the repository.

## Constraints

- No network; nothing may be installed or fetched.
- Do not read or modify `/opt/golden`, `/tests` or `/solution`; they are
  harness-owned.
- Do not commit, re-roll, fetch or otherwise mutate the repository's history;
  `HEAD` must stay at the pinned commit and the only difference from it is
  your source fix. Do not add or delete files inside the repository.

## What the verifier checks

1. Provenance: `HEAD` is still the pinned commit; the repository state differs
   only by the minimal source fix; your reproduction file exists, is
   executable, and invokes the project's own test runner.
2. Your reproduction against the pre-fix tree (must fail and print a failing
   test run) and against your repaired tree (must pass).
3. The project's own upstream regression tests for this bug (run with `go
   test`) pass against your tree.
4. The project's own existing promtool test suite passes end to end, proving
   the fix broke nothing else.
5. Two hidden cases authored for this task exercise the same code path with
   inputs the upstream tests do not use.

Deliverable: the fixed `/app/src` plus your authored `/app/repro.sh`.