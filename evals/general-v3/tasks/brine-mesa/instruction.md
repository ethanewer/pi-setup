# Brine-Mesa — deterministic O(n) drift simulator, serial + OpenMP

Coastal-drift labs at Brine Mesa study aeolian sand transport. You must ship a
native pair of simulators — a **serial** build and an **OpenMP** build of the
same spatially-binned O(n) particle model — plus a report from the shipped
fixture. The verifier runs both binaries on the visible fixture and on hidden
fixtures and compares them against reference data, so the model must follow the
specification below **exactly**.

## Deliverables (all three required)

1. **`/app/drift_serial`** — executable, built **without** OpenMP.
   `./drift_serial INPUTFILE OUTPOSFILE`
2. **`/app/drift_omp`** — executable, built **with** OpenMP from the same
   model. `./drift_omp INPUTFILE OUTPOSFILE`
3. **`/app/report.json`** — JSON report of running both binaries on the
   shipped fixture `/app/fixture_main.txt` (schema below).

Do **not** modify `/app/fixture_main.txt`.

## Input file format

```
N CUTOFF DT STEPS LX LY LZ          # ints N, STEPS; doubles elsewhere
x y z vx vy vz                      # N lines, doubles
```

## Model (implement exactly; both binaries must be numerically identical)

For each of the `STEPS` steps:

1. **Bin** every particle by its current wrapped position into a uniform cell
   grid with `ncx = max(1, floor(LX/CUTOFF))` cells along x (same for y, z),
   cell size `hx = LX/ncx` (so `hx >= CUTOFF` unless the whole axis is a single
   cell). Cell lookup for particle p: `cx = clamp((int)(px/hx), 0, ncx-1)`,
   same for y/z. Each cell's particle list must be in **increasing index
   order** (e.g. counting sort).
2. **Force pass** — computed for ALL particles from the current positions
   (zero the accumulators first). For particle `i` (this per-particle loop is
   what you parallelize over; every particle's force is independent):
   - Let `(cxi, cyi, czi)` be i's cell. For `dcx = -1..1`, then `dcy = -1..1`,
     then `dcz = -1..1` (nested in exactly this order):
     `cx = ((cxi+dcx) % ncx + ncx) % ncx` (same for cy, cz); iterate the
     cell's particles `j` in increasing index order, `j != i`:
     - `dx = px[i]-px[j]`; minimum image: `dx -= LX*round(dx/LX)` (C `round`:
       half away from zero); same for dy, dz.
     - `r2 = dx*dx+dy*dy+dz*dz`; skip if `r2 < 1e-12` or `r2 >= CUTOFF*CUTOFF`.
     - `r = sqrt(r2)`; `f = (1.0 - r/CUTOFF) / r`; `fx[i] += f*dx;` likewise
       fy, fz.
3. **Integrate** every particle (per-particle, independent): `vx += fx*DT`,
   then `px += vx*DT`, then wrap: `px -= LX*floor(px/LX)` (same y, z).
4. **Motion metric**: while integrating each step, measure the per-particle
   displacement **before** wrapping; `moved` = the maximum over all particles
   and all steps of `sqrt(dx^2+dy^2+dz^2)` for that per-step displacement.

Because each particle's force and integration depend only on the *previous*
step's state and is accumulated in the fixed order above, the model is
bit-for-bit deterministic regardless of thread count. Your `drift_omp` output
must match your `drift_serial` output exactly.

## Output contract (both binaries)

- `OUTPOSFILE`: exactly `N` lines, the final wrapped positions, one particle
  per line.
- stdout: exactly one line, `threads=<T> seconds=<S> moved=<M>` where
  - serial build: `T = 1`;
  - OpenMP build: `T` = the maximum number of threads observed in any parallel
    region (`omp_get_num_threads()` inside the parallel force loop); **must be
    >= 2** in this environment;
  - `S` = wall-clock seconds of the step loop (`%.3f`), `M` = `moved`
    (`%.6f`).

## report.json schema (visible fixture)

```json
{
  "serial": {"threads": 1, "seconds": <float>, "moved": <float>},
  "omp":    {"threads": <int>=2, "seconds": <float>, "moved": <float>},
  "positions_match": true,
  "ok": true
}
```

## What the verifier does

- Checks `/app/fixture_main.txt` is unmodified and the deliverables exist.
- Runs `drift_serial` on the visible fixture and on every hidden fixture
  (small/edge, medium, and a large `N=100000` timing fixture) and compares the
  final positions against reference data (minimum-image distance tolerance
  1e-6) and `moved` against the reference value; the large fixture must finish
  quickly (a quadratic implementation will time out — the binned model is
  O(n)).
- Runs `drift_omp` on every fixture: positions must match the serial run
  **exactly**, `threads >= 2`, and on the large fixture the OpenMP run must be
  faster than the serial run (real parallelism, not an ornament).
- Inspects `drift_omp` for genuine OpenMP linkage (GOMP symbols) — a binary
  that never actually threads, or an MPI/orphan build without the required
  outputs, fails.
- Cross-checks `/app/report.json` against its own observed runs.
