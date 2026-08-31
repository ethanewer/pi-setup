# Coral Forge — Aeolus wind-tunnel mean-field particle solver

The Aeolus group models dust/debris transport in a 100 m x 100 m wind-tunnel
section with a **mean-field** particle solver: every particle feels a pull
toward the centroid of the spatial bin it currently occupies (a 16x16 bin
grid). That keeps each particle's update **O(1)** and the whole step **O(n)**
— no O(n^2) pair loops are acceptable.

You must author the complete native solver under `/app/wind` and a Python
driver that builds it and reports measured results. The solver exists as two
binaries compiled **from one source**: a serial build and an OpenMP build.
Both must compute **bit-identical physics**, and the particles must **genuinely
move** (non-zero displacement).

Working directory: `/app`. Available: `gcc`, `make`, `libomp-dev` (OpenMP),
`python3`. Everything runs offline in this one container.

## Deliverables (all required)

1. `/app/wind/solver.py` — the Python driver (see contract below).
2. `/app/wind_report.json` — the report the driver wrote for the shipped
   fixture `/app/case_main` (run the driver yourself once).
3. The native sources under `/app/wind/` (at minimum a `src/cloud.c` containing
   the single-source serial+OpenMP simulation, plus a build driver, e.g. a
   `Makefile`) such that `make -C /app/wind` builds:
   - `/app/wind/build/cloud_serial`  (compiled WITHOUT OpenMP)
   - `/app/wind/build/cloud_openmp`  (compiled WITH `-fopenmp`)

## Binary contract

```
cloud_serial  N STEPS DT SEED OUTBIN
cloud_openmp  N STEPS DT SEED OUTBIN
```

Print exactly three lines to stdout (one value each, in this order):

```
ELAPSED <float seconds spent in the step loop>
DRIFT <float max displacement of any particle from its initial position>
STATE <16 lowercase hex chars>
```

- `STATE` is a deterministic 64-bit checksum of ALL final state, built by
  iterating particles in index order and folding the raw IEEE-754 bit pattern
  of each particle's `x, y, vx, vy` (in that order) into an FNV-1a-style 64-bit
  hash. The serial and OpenMP builds must print the **same** `STATE` and the
  same `DRIFT` for the same arguments.
- `OUTBIN` receives the final state as raw little-endian doubles, 4 per
  particle (`x, y, vx, vy`), in index order.
- `ELAPSED` measures the simulation step loop only
  (`clock_gettime(CLOCK_MONOTONIC)` around it). Keep the inner work real — a
  per-particle fixed-length scalar recurrence fed by the particle's own
  coordinates — so timing is meaningful and the work cannot be elided at
  `-O2` (e.g. a `volatile` accumulator).

## Physics (must be implemented as specified)

- Deterministic LCG seeding from `SEED` (any standard 64-bit LCG is fine);
  initial positions uniform on `[0, 100)` in both axes; initial velocities
  small and symmetric.
- Every step:
  1. bin all particles on the 16x16 grid over `[0,100)^2` and compute each
     **occupied** bin's centroid (mean of member positions). Empty bins never
     exert force. This pass is serial in both builds.
  2. update every particle in parallel (OpenMP parallel-for writing only that
     particle's `x, y, vx, vy`): a spring toward its bin centroid
     (coefficient `-0.05` scaled by the offset), then a per-particle CPU-bound
     scalar recurrence (fixed ~24 iterations depending on the particle's
     coordinates), then the velocity/position integration with time step `DT`.
  Per-particle arithmetic must depend only on that particle's own state plus
  the (serially computed) bin centroids, so the OpenMP build is bit-identical
  to serial.

## Driver contract — `/app/wind/solver.py`

```
python3 /app/wind/solver.py            # run the shipped fixture /app/case_main
python3 /app/wind/solver.py run DIR    # run the fixture directory DIR
```

- Build the binaries first (idempotently, e.g. `make -C /app/wind`), run both
  builds on the fixture, and write `/app/wind_report.json`.
- A fixture directory contains `params.ini` with `key=value` lines: `N`,
  `STEPS`, `DT`, `SEED`, and optionally `BENCH=1`. Missing `N`/`STEPS`/`DT`/
  `SEED` must fall back to sane defaults (the run must still succeed and be
  deterministic for a given fixture).
- `/app/wind_report.json` schema (exact keys):

```json
{
  "task": "coral-forge",
  "n": 80000,
  "steps": 30,
  "dt": 0.01,
  "seed": 1234,
  "bench": true,
  "serial_elapsed": 1.834,
  "openmp_elapsed": 0.921,
  "speedup": 1.99,
  "drift": 0.4127,
  "state": "9f1c2ab04d5e6f70",
  "match": true,
  "motion": true,
  "ok": true
}
```

- `speedup` = `serial_elapsed / openmp_elapsed`; `match` = serial and OpenMP
  agreed on `STATE`/`DRIFT`; `motion` = drift is non-zero; `ok` = clean run.
- Values must be the **actual** measured outputs of the two binaries — the
  verifier re-runs the binaries itself and cross-checks.

## What the verifier does

- Re-runs `python3 /app/wind/solver.py run <hidden fixture>` on fresh fixture
  directories (same `params.ini` schema), then independently re-runs both
  built binaries on the same parameters and requires:
  - `STATE` equality between serial and OpenMP builds (report and re-run);
  - `DRIFT > 0` — particles genuinely move;
  - the reported `state` equals the independent re-run's `STATE`;
  - `cloud_openmp` is genuinely OpenMP-linked (libgomp) and `cloud_serial`
    is not;
  - on `BENCH=1` fixtures: measured speedup within `1.05 <= speedup <= 8.0`
    and the serial step loop long enough to be meaningful (`serial_elapsed`
    >= 0.05 s). Non-bench fixtures skip the speedup window.
- Missing/extra keys or non-numeric garbage in the report fails; never
  fabricate.

## Constraints

- Keep the solver O(n) per step. The bench fixture runs `N=120000`, `STEPS=40`
  in a couple of seconds — anything super-linear will blow the budget.
- Deterministic: same fixture + binaries => identical `STATE` every run.
- Do not modify `/app/case_main`; everything offline.
