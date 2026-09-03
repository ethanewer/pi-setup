# Glacier Basin — duration-sharding, bail-on-failure, and per-launcher reporting for the mini-runner harness

The harness at `/app/harness/` is a mini test runner. It discovers test cases
from a `suite.json` manifest (`id`, `launcher`, `duration_ms`, `deps`) and
currently runs everything through a **single launcher**, sequentially, writing
a flat results file. Your job is to **extend the runner** so a suite can be
split across **K launcher bins** with duration-balanced sharding, aborted
early on failure, and reported per launcher plus as one aggregate, and to
**deliver the run report for the visible suite**.

## Fixtures (already in `/app`, read-only)

- `/app/harness/runner.py` — v1 runner (sequential, single launcher, writes
  `flat-results.json`). Extend this file (you own it now).
- `/app/harness/README.md` — notes on the manifest shape.
- `/app/suites/visible.json` — the visible suite manifest.

## Deliverables

1. `/app/harness/runner.py` — the extended runner implementing the v2 contract
   below, driven exactly like this:
   ```
   python3 /app/harness/runner.py --suite /app/suites/visible.json --out /app/run_report --k 3 --bail
   ```
2. `/app/run_report/` — the outputs that command produces for the visible
   suite, including `params.json` recording `k` and `bail` (you may choose any
   `k >= 1` and bail on/off; `3` with bail on is a good showcase).

## Suite manifest (v2 schema)

```json
{
  "name": "visible",
  "cases": [
    {"id": "auth-basic", "launcher": "unit", "duration_ms": 340, "deps": [], "fail": false}
  ]
}
```

- `id` — unique, non-empty string.
- `launcher` — free-form logical-launcher tag; it is **echoed into the per-case
  result and never influences scheduling**.
- `duration_ms` — nominal duration, positive integer.
- `deps` — list of case ids that must **pass** before this case may run. Deps
  form a DAG and the manifest is **topologically sorted: every dependency
  appears earlier in the `cases` array than its dependents**.
- `fail` — optional bool, default `false`. The runner **simulates** execution
  (durations are nominal, launchers are logical names), so pass/fail is static:
  a case that runs with `fail: true` fails, otherwise it passes.

## The v2 runner contract

### CLI

```
python3 /app/harness/runner.py --suite <suite.json> --out <outdir> --k <K> [--bail]
```

`--k` is a positive integer (number of launcher bins). `--bail` is an optional
flag; absent means bail is off. The runner creates `<outdir>` if missing,
overwrites its own files, prints a one-line summary, and exits 0. Invalid
arguments, unreadable suites, duplicate ids, unknown dep ids, non-positive
durations, or a manifest that violates deps-before-dependents must exit nonzero
with an error on stderr. Behavior is fully deterministic: the same suite and
flags always produce identical report content (no wall-clock fields, no
timestamps, no randomness).

### Output files (exactly these, written into `<outdir>`)

`params.json`:
```json
{"suite": "visible", "k": 3, "bail": true}
```

`report.json` (aggregated, CTRF-like):
```json
{
  "schemaVersion": "2.1",
  "framework": {"name": "mini-runner", "version": "2.0.0"},
  "suite": "visible",
  "k": 3,
  "bail": true,
  "toolRun": {
    "numTotalTestCases": 8,
    "numPassedTests": 5,
    "numFailedTests": 1,
    "numSkippedTests": 2,
    "totalDurationMs": 1860
  },
  "results": [
    {"id": "auth-basic", "launcher": "unit", "shard": 2, "status": "passed",
     "duration_ms": 340, "deps": [], "skip_reason": null}
  ]
}
```

One `launcher-<i>.json` per bin, `i` in `0..K-1` (all K files are always
written, empty bins included):
```json
{
  "launcher": 0,
  "cases": ["auth-token", "e2e-sync"],
  "numPassed": 1,
  "numFailed": 0,
  "numSkipped": 1,
  "durationMs": 180,
  "nominalLoadMs": 790,
  "bailed": false
}
```

### 1. Sharding — LPT (longest-processing-time-first)

Sort the cases by `(-duration_ms, id)` — duration descending, ties broken by
`id` ascending (plain lexicographic string order). Walk that order and place
each case into the bin with the **smallest current total load**; ties broken by
**lowest bin index**; a case's load is its `duration_ms`. The resulting bin
index is the case's `shard`. Per-launcher `cases` lists and results order stay
in **manifest order**.

### 2. Bail mode and dependency rules

Simulate the run in manifest order (valid because deps always precede their
dependents). Track per-bin `bailed` state and per-case status
(`passed`/`failed`/`skipped`). For each case, in order:

1. If any **dependency did not pass** (status `failed` or `skipped` — it does
   not matter why), the case is `skipped` with `skip_reason: "dep"` and
   `duration_ms: 0`.
2. Else, if **bail is on** and the case's bin has **already bailed** (an earlier
   case in that bin failed), the case is `skipped` with `skip_reason: "bail"`
   and `duration_ms: 0`.
3. Else the case **runs**: status `passed` or `failed` per its `fail` flag,
   `duration_ms` equals its nominal `duration_ms`, `skip_reason` is `null`.
   If it failed and bail is on, its bin's `bailed` flag becomes true (the
   launcher stops). With bail off, later cases in the same bin still run.

Note the precedence: `"dep"` outranks `"bail"` whenever both apply, and
bail-only skipping (`"bail"`) happens solely because the bin stopped — cases
that could not run due to dependencies are always `"dep"`.

### 3. Reports

- `results` in **manifest order**; each entry: `id`, `launcher`, `shard`,
  `status`, `duration_ms`, `deps` (echoed as in the manifest), `skip_reason`.
- `toolRun` counts: `numTotalTestCases` = all cases; `numPassedTests`,
  `numFailedTests`, `numSkippedTests`; `totalDurationMs` = sum of `duration_ms`
  across `results` (skipped cases contribute 0).
- Per launcher `<i>`: `cases` = assigned ids in manifest order;
  `numPassed`/`numFailed`/`numSkipped` over those cases; `durationMs` = sum of
  their run durations (0 for skipped); `nominalLoadMs` = the LPT load
  (sum of all assigned nominal durations); `bailed` = whether the bin stopped
  on a failure.

## How the grader probes it

The verifier **executes `/app/harness/runner.py`**: it re-runs it on the
visible suite using the `k`/`bail` recorded in your delivered
`/app/run_report/params.json` and requires the regenerated report files to
equal your delivered ones; and it runs it on **hidden suites** (uneven
durations, cross-shard dependency chains, all-fail and all-pass suites, `K`
larger than the case count, duration ties binding on id order) under several
`--k`/`--bail` combinations, independently recomputing the LPT shard
assignment, the bail cascade, and every report file, and requiring **exact
JSON equality**. A runner that special-cases the visible suite cannot pass the
hidden suites. Work only under `/app` using the Python standard library; no
network.