# cedar-canyon: ship a native C/C++ math stack and a reproducible driver

You are given a fresh container (Ubuntu 24.04 with `make`, `cmake`, `gcc`,
`g++`, `clang`, `libomp-dev`, `python3`). There is **no** pre-existing project
to repair — the whole stack is yours to author. Your job is to create a small
native C/C++ "math stack" at **`/app/math`** and a reproducible Python driver
that builds it and exercises every tool, writing a machine-readable report.

Working deliverables (the only things the verifier touches):

1. **`/app/solve.py`** — a Python driver (make it executable) with two modes:
   * **Default** (`python3 /app/solve.py`): build the stack, run it against the
     shipped workbench fixture `/app/sample_fixture`, and write
     **`/app/answer.json`**. Re-running it must reproduce the same report.
   * **Run** (`python3 /app/solve.py run DIR`): build the stack (idempotent),
     run every tool against the fixture in `DIR`, and write `/app/answer.json`.
     This is what the verifier uses on fresh / hidden fixtures (see below). It
     must never crash.
2. **`/app/answer.json`** — written by solve.py. Schema (exact keys):

   ```json
   {
     "task": "cedar-canyon",
     "max_square": 9,
     "binding_prefix": [0.0, 2.5, 9.0, -1.0],
     "serial_s": 0.482,
     "parallel_s": 0.251,
     "speedup": 1.92,
     "move": 0.371,
     "positions_match": true,
     "sampler_argmax": [0, 2, 1],
     "llvm_ir": ["/app/math/build-emit/ir/sim_c.ll"],
     "ok": true
   }
   ```
   `max` is the maximal-square area; `binding_prefix` the exact running-sum
   from the native binding (list of doubles, one per input value);
   `serial_s`/`parallel_s`/`speedup` the measured simulation times and their
   ratio (`serial_s / parallel_s`); `move` the max particle displacement;
   `positions_match` whether the serial and OpenMP runs agree bit-for-bit;
   `sampler_argmax` the arg-max token sequence; `llvm_ir` the emitted `.ll`
   paths; `ok` true on a clean run.

---

## The math stack (`/app/math`)

Author the sources yourself (any file names you like inside `/app/math`) with
this shape:

```
/app/math/
  Makefile          build driver
  CMakeLists.txt    also present; CMake emits per-TU LLVM IR
  src/
    sim.c           particle simulation (serial + OpenMP from ONE source)
    natc.c          native ctypes binding (cumulative / running-sum)
    pick.c           plain-C arg-max parser (sampler)
    port.cpp        a C++11/14 constexpr template port
```

### 1. Particle simulation — `sim_serial` and `sim_openmp`

Compile the **same** `sim.c` twice: once without OpenMP
(`bin/sim_serial`), once with `-fopenmp` (`bin/sim_openmp`). The simulation
must be **O(n) per step** (spatial binning / center-of-mass style, per-particle
O(1) update, no O(n^2) neighbour loops) and produce **genuine motion**: the
positions must change from the initial layout across the steps.

CLI: `sim N STEPS_SEED OUTFILE` — prints to stdout exactly two lines:

```
TIME <elapsed-seconds (float)>
MOVE <max-displacement-check (float)>
SUM <uint64-hex>
```

`SUM` is a deterministic checksum of ALL final positions (built by iterating
the `x`/`y` arrays in index order and folding each double's raw bits into a
64-bit hash). The serial and the OpenMP runs must print **identical** `SUM`
and identical `MOVE` values — the two variants compute identical physics.

`TIME` is the wall time spent in the full simulation update loop
(use `clock_gettime(CLOCK_MONOTONIC, ...)` around the step loop). Use a
`volatile` accumulator fed by the inner compute so the work is never elided
by `-O2`.

Concretely, keep the inner update CPU-bound so threading is measurable
(*e.g.* a fixed 24-iteration per-particle scalar recurrence that depends on
the particle's coordinate) — anything equivalent is fine.

Use `OMP_NUM_THREADS` to control parallelism (the driver sets it to the
machine's core count). The OpenMP parallel-for must write each particle's
`x[i],y[i]` independently so the arithmetic is bit-identical to serial.

### 2. Native binding — `libnatc.so` (ctypes)

`src/natc.c` exposes a C function used through Python `ctypes`:

```c
long prefsum(const double* in, long n, double* out);
```

It computes the running (prefix) sum: `out[i] = in[0]+...+in[i]` for all
`i in [0,n)`, and returns `n`. The **known bug you must patch**: the current
binding has a length/alias mismatch and returns an all-zero (or otherwise
degenerate) buffer instead of the real running sums. Fix the C so the returned
array equals the mathematical prefix sum for **every** `n` (including `n == 1`
and odd/even lengths). The driver loads it via:

```python
import ctypes
lib = ctypes.CDLL("/app/math/bin/libnatc.so")
lib.prefsum.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_long, ctypes.POINTER(ctypes.c_double)]
lib.prefsum.restype = ctypes.c_long
```

There is a reference Python implementation — the driver uses it to verify that
each output element matches the true running sum (compare with a small
relative/absolute tolerance for floats).

### 3. Maximal-square — `solve.maximal_square(grid)`

`/app/solve.py` (the module itself) must define, at import time, a pure-Python
function:

```python
def maximal_square(grid) -> int
```

`grid` is a list of rows where each row is either a single string of `0`/`1`
characters (e.g. `"10101"`) or a list of integers `0/1`. It returns the area
(`side*side`) of the largest square whose cells are all `1`, or `0` if there
is no such square. It must be importable without running the driver
(`from solve import maximal_square` must not trigger any engine build or
subprocess). Edge cases you must handle:

* empty grid / empty first row → `0`
* a single row / single column grid → `1` if that cell is `1`, else `0`
* all-zero grid → `0`
* all-one grid → `rows*cols` (the largest full square)
* varying per-row lengths → use the number of columns as the min length of the
  rows that are present; a row shorter than the width is treated as padded
  with `0`

The verifier will call `maximal_square` via `import solve` on hidden grids
(including all of the above adversarial shapes).

### 4. Arg-max sampler (feels like flavor; must still work)

A tiny CLI `pick` that reads rows of space-separated numbers on stdin and prints
one line per row with the **0-based column index of the maximum value**
(`argmax`, first occurrence wins). The driver feeds a `weights.txt` fixture
through it and records the sequence as `sampler_argmax`.

### 5. CMake → LLVM IR per translation unit

Add a **CMakeLists.txt** (at `/app/math`) with a target that, for **every**
translation unit (`sim.c`, `natc.c`, `picker.c`, `port.cpp`), emits the
corresponding **LLVM IR** as `<name>_<ext>.ll` under
`/app/math/build-emit/ir` directory. The driver builds it with:

```
cmake -S /app/math -B /app/math/build-emit
cmake --build /app/math/build-emit --target ir
```

After the build these files must exist and be non-empty:
`sim_c.ll`, `natc_c.ll`, `picker_c.ll`, `port_cpp.ll`. (You may also keep a
`Makefile` that conveniences the binary build; verifier checks the `.ll`
paths: their exact path is not fixed beyond "inside `build-emit`".)

## Fixture schema (same as `/app/sample_fixture`, and as every hidden case)

`DIR` passed to `run DIR` contains:
* `values.txt` — one float per line (may include negatives, `0`, a single
  value, a long list; a blank/empty file means empty list → empty prefix).
* `grid.txt` — rows of `0`/`1` characters; may be empty, a single row, ragged
  (shorter rows), an all-one square, or an all-zero grid.
* `sim.ini` — `key=value` lines: `N`, `STEPS`, `SEED`, and optionally
  `BENCHMARK=1` (present exactly on the benchmark-case; only then the verifier
  enforces the speedup window). Missing `N`/`STEPS` → sane defaults (and the
  run must still succeed).

The verifier copies each hidden `DIR` to a writable temp location, runs
`python3 /app/solve.py run <tmpdir>`, reads `/app/answer.json`, and then
independently recomputes the prefix-sums (reference Python), the maximal-square
area, the particle positions/checksum/timing by re-running the compiled
binaries, and inspects the `.ll` files. It also calls `solve.maximal_square`
directly. So do **not** fabricate `answer.json` values — they must be the
actual outputs of the tools, and the tools must be present and runnable.

## Constraints

* All source code lives under **`/app/math`** and all deliverables
  (`solve.py`, `answer.json`) at `/app/`.
* Do not touch anything under `/tests` (mounted read-only) and never read it.
* Keep the sim `O(n)` — huge `n*steps*inner` must stay a few seconds.
* Everything must run offline in one container (no network, no systemd, no
  GPUs). 

## How you will be graded (read-only)

The verifier re-invokes `/app/solve.py` on more hidden fixtures and
independently re-checks:
* `from solve import maximal_square` returns the exact area for adversarial
  grids (empty, single row/col, all-zero, all-one, ragged);
* the native binding running-sum equals the reference for hidden `values.txt`
  (including negatives, a single value, odd lengths, long lists);
* `sim_serial` and `sim_openmp` both run a hidden `sim.in` and print agreement
  on `SUM`/`MOVE`, `MOVE > 0` (genuine motion), exact serial==openmp checksum
  agreement, and on the `BENCHMARK=1` fixture the measured speedup sits in the
  required window (`1.10 <= speedup <= 5.0`) and the parallel absolute time is
  not artificially inflated to cheat the ratio.

So the interplayer: you fix the binding, you implement a real parallel sim with
genuine motion, you write the DP, and a driver that honestly reports measured
metrics. If any one of those is missing or wrong, the verifier fails.