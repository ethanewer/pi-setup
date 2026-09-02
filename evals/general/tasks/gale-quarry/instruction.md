# gale-quarry — ship an O(n) drifting-mote simulation (serial + OpenMP)

You are the simulation engineer for the **Kestrel Drift Survey**. A swarm of
`N` motes drifts on the unit torus `[0,1)^2`. Your job is to author a **single
C source file** that implements an **O(n) per step** spatial-binned update,
compile it twice from the *same* source — once plain, once with OpenMP — and
ship a Python driver that builds, runs, and reports. The particles must
**genuinely move**, and the OpenMP variant must compute **bit-identical
physics** to the serial one.

Everything lives under `/app` (Debian, Python 3.12, `gcc` with OpenMP
available). Do **not** modify `/app/scenario.ini`.

## Deliverables (all three required)

1. `/app/src/motes.c` — one C source implementing the simulation (below).
2. `/app/launch.py` — the Python driver (below).
3. `/app/result.json` — the driver's report for the visible scenario
   `/app/scenario.ini` (produced by running `python3 /app/launch.py`).

## The simulation (`/app/src/motes.c`)

CLI (exactly four arguments):

```
motes N STEPS SEED OUTFILE
```

- Initialise `N` particles deterministically from `SEED` (any documented,
  reproducible rule; the two builds share it).
- Run `STEPS` updates. **Each step must be O(n)**: bin particles into a fixed
  `G x G` spatial grid (e.g. 64x64) with a single O(n) pass computing each
  occupied cell's count and centre-of-mass, then give every particle an
  **O(1)** update pulled toward its cell's centre-of-mass plus a tangential
  swirl term, wrapping positions back into `[0,1)`. Any per-particle O(1)
  scheme of that shape is acceptable; an O(n^2) all-pairs neighbour loop is
  not.
- Keep a fixed per-pinner scalar recurrence inside the update (e.g. a
  24-iteration floating-point recurrence seeded by the particle's own
  coordinates) so the per-step work is genuinely CPU-bound and cannot be
  optimised away — and make its value (however slightly) influence the
  particle's motion so the compiler must keep it live.
- On stdout print exactly three lines:

```
TIME <elapsed-seconds of the step loop, float>
MOVE <max displacement of any particle from its initial position, float>
HASH 0x<16 hex digits>
```

- `HASH` is a deterministic 64-bit checksum over **all** final positions
  (iterate the x and y arrays in index order, folding each double's raw IEEE
  bits into a 64-bit FNV-style hash). The two builds must print identical
  `HASH` **and** identical `MOVE` — the physics is bit-identical.
- Write the final positions to `OUTFILE` as `2N` little-endian doubles
  (all x, then all y).
- Use `clock_gettime(CLOCK_MONOTONIC, ...)` around the step loop for `TIME`.

Compile the **same file** two ways:

- `/app/bin/motes_serial` — `gcc -O2 -o /app/bin/motes_serial /app/src/motes.c -lm`
- `/app/bin/motes_openmp` — `gcc -O2 -fopenmp -o /app/bin/motes_openmp /app/src/motes.c -lm`

The OpenMP build must use a real `#pragma omp parallel for` over the
per-particle update (each particle writes only its own `x[i], y[i]`, so the
arithmetic stays bit-identical to serial). The grader inspects the OpenMP
binary for genuine OpenMP use (the `GOMP_parallel` symbol and a `libgomp`
dependency must both be present); a binary merely *named* openmp, or an
MPI-orphaned stub, fails.

## The driver (`/app/launch.py`)

- **Default** — `python3 /app/launch.py` (no args): build both binaries
  (idempotently), run them on the shipped scenario `/app/scenario.ini`, and
  write `/app/result.json`.
- **Run mode** — `python3 /app/launch.py run DIR`: same, but the scenario is
  `DIR/scenario.ini`. This is what the grader uses on hidden scenarios; it
  must never crash on any scenario following the schema below.

`scenario.ini` is `key = value` lines with integer keys `N` (>= 1),
`STEPS` (>= 0), `SEED`, and an optional `MOTION` flag (`1` = the grader will
require genuine displacement). Blank lines and `#` comments are allowed.

`/app/result.json` must have exactly these keys:

```json
{
  "task": "gale-quarry",
  "n": 80000,
  "steps": 120,
  "seed": 20260228,
  "serial_hash": "0x...",
  "openmp_hash": "0x...",
  "match": true,
  "move": 0.371,
  "serial_ms": 1234,
  "openmp_ms": 701,
  "threads": 2,
  "openmp_linked": true,
  "ok": true
}
```

- `serial_hash` / `openmp_hash` are the two binaries' `HASH` lines verbatim;
  `match` is true iff both `HASH` and `MOVE` lines agree across the builds;
  `move` is the serial `MOVE` value as a float; `serial_ms` / `openmp_ms` are
  the two `TIME` values in whole milliseconds; `threads` is the
  `OMP_NUM_THREADS` value you used for the OpenMP run; `openmp_linked` is
  true iff the OpenMP binary is genuinely OpenMP-linked (check e.g. `ldd`
  for `libgomp`); `ok` is true iff `match` and `openmp_linked` hold.
- Values must be the **actual measured outputs** — the grader re-runs both
  binaries itself on the same `N STEPS SEED` and compares.

## What the grader will do

- Execute `python3 /app/launch.py` on the visible scenario and
  `python3 /app/launch.py run <hidden-dir>` on every hidden scenario, then
  read `/app/result.json` and validate the schema and the `ok`/`match`/
  `openmp_linked` fields.
- Independently re-run `/app/bin/motes_serial` and `/app/bin/motes_openmp`
  with each scenario's `N STEPS SEED` and require both `HASH` lines to agree
  with each other and with `result.json`, the positions file to be `16*N`
  bytes, and — on scenarios with `MOTION = 1` — `MOVE > 0` (real motion).
- Inspect the OpenMP binary for `GOMP_parallel` / `libgomp` and require the
  serial binary to run without OpenMP linkage.
- Keep runtimes modest: with the shipped parameter ranges every binary run
  finishes in a few seconds; something super-linear in `N` will blow the
  grader's per-case timeout.

## Constraints

- All sources under `/app/src`; binaries under `/app/bin`; driver and report
  at `/app`.
- Offline, single container, standard library only for the driver.
- Deterministic: identical `N STEPS SEED` must always reproduce identical
  `HASH`, `MOVE`, and positions bytes.
