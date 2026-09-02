# raven-jetty — C reuse + toolchain bench

You are the toolchain engineer for the **raven-jetty** imaging line. Four jobs
are on your bench. Each job has a written contract, exact paths, and exact
formats. The grading harness re-runs your scripts and re-executes your
binaries from scratch; there is no credit for hand-written output files that
do not come from working scripts. Work entirely inside `/app`.

Toolchain available in the image: `gcc`, `clang`, `make`, `bash`, `python3`,
plus the standard `binutils` (`ar`, `readelf`, ...) and `file`. There is no
network access and no package index at runtime; everything you need is already
installed.

## Fixtures shipped in the image (do not modify)

* `/app/behavior-spec.txt` — the recovered-behavior contract for Job 1.
* `/app/engine/include/hull/engine.h` — the engine's public header (Job 2).
* `/app/toycc.c` — the as-shipped toy compiler source (Job 4). **This one you
  are expected to modify: fixing it is the task.**

Do not edit `/app/behavior-spec.txt` or anything under `/app/engine/`.

---

## Job 1 — standalone clone of the recovered behavior  (`/app/clone/`)

The legacy `tx-71` loader's wire transform, called the **shoal** transform,
was recovered but the loader itself is gone. Reimplement it as a fully
standalone C program.

* Read `/app/behavior-spec.txt` and implement **exactly** the byte transform
  it documents (reverse the byte order, then run a weave that XORs each
  reversed byte with a running key that starts at `0xC1` and advances by
  `(k + v + 0x0D) & 0xFF` after each byte).
* Create `/app/clone/app.c` and `/app/clone/Makefile`. The Makefile's default
  target must build a **statically linked** executable named `app` from
  `app.c` (use `-static`; the image supports it).
* Your `app` reads bytes from **standard input** and writes the transformed
  bytes to **standard output**, then exits 0. It must handle:
  * an empty input stream (produce zero output bytes, exit 0),
  * arbitrary 8-bit bytes including `0x00` and `0xFF`,
  * arbitrarily long input (no fixed cap).
* The build and binary must be self-contained:
  * no reads of any file at runtime (stdin/stdout only),
  * no `#include` of anything outside the C standard library headers,
  * no reference (in source or strings) to the original loader or to the
    `/app` tree — it must run in a clean scratch directory with only
    `app.c` + `Makefile` present, compiled there with `make`, with no network.
* Build it so `/app/clone/app` exists and works. You may add `make clean`
  handling, compiler flags, comments, etc., but the default `make` in a clean
  directory containing only `app.c` + `Makefile` must produce `app`.

## Job 2 — engine header on the include path  (`/app/include-path.sh`)

The engine's public header `hull/engine.h` sits in
`/app/engine/include/hull/engine.h`. Downstream tools include it with angle
brackets: `#include <hull/engine.h>`. Without configuration `clang` cannot
find it.

* Create `/app/include-path.sh`, a `bash` script that:
  1. adds `/app/engine/include` to the C/C++ preprocessor include path,
  2. compiles the following probe with **clang**:
     ```c
     #include <hull/engine.h>
     #include <stdio.h>
     int main(void) { printf("probe hull_level=%d tag=%s throttle=%d\n",
                             HULL_LEVEL, HULL_TAG, (int)HULL_TAKEOFF);
                       return 0; }
     ```
  3. runs it and writes the run's stdout to `/app/include-proof.log`,
  4. exits 0 only if compilation and run both succeed.
* You may implement the include path with the `CPATH`, `C_INCLUDE_PATH` or
  `-I` mechanism — any genuine include-path configuration that makes
  `clang` resolve `<hull/engine.h>` is accepted. The script must not hard-code
  the answer; the probe output itself must come from actually compiling and
  running the included header.
* `/app/include-proof.log` must therefore contain a line with the engine's
  real values, e.g. `probe hull_level=9 tag=raven-weave throttle=2`. Any value
  or format is fine as long as it came from the header via the include path.

## Job 3 — distinct build modes  (`/app/build-modes.sh`)

You will compile ***one*** C source under two distinct flag sets plus
instrumentation, then run each build and record each one's behavior.

* Create `/app/build-modes.sh`, a `bash` script that:
  1. writes a small C program `bmsrc.c` into the current directory. The
     program takes two optional integer arguments (default `lo = 1`,
     `hi = 100`) and computes `acc = sum of every integer from lo to hi
     inclusive`.
  2. builds **four executables** from that same source with **distinct**
     flag sets:
     * `bm_fast`   — optimized, assertions off:  `gcc -O2 -DNDEBUG`
     * `bm_debug`  — assertions on + **coverage instrumentation**:
       `gcc -g -O0 --coverage`
     * `bm_release`— plain optimized: `gcc -O2`
     * `bm_trace`  — asserts on, no coverage: `gcc -g -O0`
  3. the source must print different mode behavior depending on the build,
     for example via `#ifdef NDEBUG` (a debug/assert build prints one
     behavior string and/or a different computed value than the NDEBUG
     build). Anything that makes the two builds observably distinct is
     acceptable, but the distinction must be real and produced by the flags.
  4. runs `bm_fast "$@" `> mode-fast.log` and `bm_debug "$@" > mode-debug.log`
     in the working directory, so both logs are created there, forwarding the
     optional lo/hi arguments to each binary. Because you run the script from
     `/app`, this yields the deliverables `/app/mode-fast.log` and
     `/app/mode-debug.log`.
  5. exits non-zero if any compilation or run fails.
* Consequences you must not break:
  * only the `--coverage` build may emit coverage artifacts: compiling
    `bm_debug` must produce a `bmsrc.gcno` in the working directory, and
    running it must produce `bmsrc.gcda` there. The non-instrumented builds
    must not emit `.gcno`/`.gcda`.
  * the two log lines must reflect the *same* `lo hi acc` but **different**
    mode behavior (because of the different flags), so the logs never read
    identically. Both `/app/mode-fast.log` and `/app/mode-debug.log` must
    therefore exist as real script-generated logs.
* The script must pass arguments through, so running
  `bash /app/build-modes.sh 1001 2000` produces logs for `lo=1001 hi=2000`
  (this is how fresh inputs are checked).

## Job 4 — make the toy compiler reject unsupported VLAs  (`/app/toycc.c`)

The bench ships `toycc.c`, a deliberately *tiny* C front-end. It claims to
support only a reduced subset of C, and one feature it honestly lacks is the
**variable-length array (VLA)** — any array declaration whose size is not a
single plain decimal integer literal. A correct compiler must therefore
**report an error** for such input instead of silently compiling it.

* Read `/app/toycc.c`. As shipped it is **buggy**: its VLA-rejection path is
  disabled, so it silently accepts VLAs. Find the fault and repair the
  front-end so that it rejects genuine unsupported constructs.
* Contract for the fixed `toycc` (this is what gets checked):
  * `toycc < src.c` reads C on stdin; `toycc src.c` reads the named file.
  * It examines **each bracketed array dimension** in the source.
  * A dimension containing only spaces/tabs and one or more decimal digits is
    **supported** (`int span[64];`, `int row[ 8 ];`).
  * Any other dimension — a variable or identifier/macro, an arithmetic
    expression, or an empty `[]`) — is a **VLA** and must be rejected:
    print to stderr a diagnostic line beginning `toycc: error:` that mentions
    the variable-length array, exit **non-zero**, and print **no** `ok` line.
  * A file with no array declarators, or an empty file, is accepted (stdout
    `ok ...`, exit **0**).
  * On success print exactly `ok` plus a short report to stdout. The current
    shape `ok tokens=<N>` is retained.
* Then, with your fixed source:
  1. build the executable: `gcc -Wall -Wextra -O2 -o /app/toycc /app/toycc.c`.
  2. write a genuine VLA test source `/app/vla.c`, e.g.
     ```c
     int main(void) { int n = 9; int buf[n]; return 0; }
     ```
  3. run `/app/toycc /app/vla.c`, capturing **stderr** into
     `/app/reject.log`. The run must exit non-zero (VLA rejected), and
     `/app/reject.log` must contain the `toycc: error:` diagnostic.
* Hidden probes will recompile your `/app/toycc.c` themselves and run `toycc`
  against (a) a VLA with a variable-size array, (b) a VLA whose size uses a
  macro/expression/`[]`, (c) a source with only fixed-size arrays, and (d) an
  empty/malformed file. All four must behave exactly per the contract above.

---

## What the harness verifies (summary)

* It rebuilds your clone in a **clean scratch directory** (only `app.c` +
  `Makefile`), checks the result is statically linked, then runs `app` on
  hidden binary inputs (empty, NUL-bearing, short, and large) and compares its
  byte output to the documented transform.
* It re-runs `/app/include-path.sh` and checks `/app/include-proof.log` shows
  real engine values; it also confirms the probe *fails* to compile when the
  include path is not configured.
* It re-runs `bash /app/build-modes.sh <lo> <hi>` with fresh ranges and checks
  the two logs show the same `acc` for that range but distinct mode behavior,
  and that `.gcno`/`.gcda` appear only for the instrumented build.
* It recompiles `/app/toycc.c` and probes VLA/OK/empty cases per the contract,
  and checks `/app/vla.c` + `/app/reject.log` exist and document a rejection.

Work from `/app`. Leave every deliverable at exactly the path listed above.
Do not read `/tests` or `/solution`; they are not present in your working
tree.