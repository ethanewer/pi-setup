# FK81 Physics Lab — toolchain & modelling bundle

You are automating the build-and-verify chores of **FK81 Laboratories**, a
plasma-physics facility.  They have shipped a frozen set of sources and an
external launcher under `/app`, and you must author deliverables into `/app` so
every component of the lab runs correctly.  Work **only** under `/app`.  Do not
modify anything in `/app/sources/` or `/app/launcher.py` (these are the lab's
immutable inputs).

You will produce **six top-level deliverables**:

| deliverable          | what it is                                                    |
|----------------------|---------------------------------------------------------------|
| `/app/game.mips`     | the terrain-sampler `hop.c` cross-compiled to a **little-endian MIPS ELF** |
| `/app/main` + `/app/Makefile` | the Fortran ballistics tool, rebuilt with `gfortran` |
| `/app/poly.c`        | one source file that is valid C++ **and** C, building under both `g++` and `gcc` |
| `/app/app`           | the FK81 particle toolkit: a C CLI that also serves the release harness |
| `/app/key.txt`       | official release activation codes |
| `/app/scheme.py`     | a metacircular interpreter for the Scheme-Lite dialect |

All commands below are run from the container; a native `gcc`, `g++`,
`gfortran`, `make`, `python3`, `mipsel-linux-gnu-gcc` and `qemu-mipsel-static`
are preinstalled.

---

## 1. MIPS cross-compiled game — `/app/game.mips`

Source: `/app/sources/hop.c`.  It must be built with the **MIPS little-endian
cross toolchain** into `/app/game.mips` (a `MIPS` ELF — not an x86 binary).

```
mipsel-linux-gnu-gcc -O2 -static -o /app/game.mips /app/sources/hop.c
```

The verifier runs it under the user-mode MIPS interpreter:

```
qemu-mipsel-static /app/game.mips <boardfile> <steps>     # prints one integer
```

Contract (already implemented in `hop.c`, do **not** alter it — just build it):
`<boardfile>` is a text file: first line `W H` (width, height), followed by
`W*H` integer heights (0..99) row-major.  The rover starts with accumulator
`acc=0` and 32-bit LCG seed `0x12345678`; for each step `i` from 1..steps it
visits cell `(i-1) % (W*H)` in row-major order, folds the height and an LCG
slice into `acc` using unsigned 32-bit wraparound, and finally prints `acc` as
a single unsigned decimal.  Your job is only to **cross-compile it** into a
MIPS ELF with the mipsel toolchain and make sure the binary prints the same
value the *native* C source computes.  Verify with the `file` command that
`/app/game.mips` is a MIPS binary.  (Build it `-static` so it runs under
`qemu-mipsel-static` with no external MIPS loader.)

## 2. Fortran tool — `/app/main` + `/app/Makefile`

Sources: `/app/sources/geom.f90` (module `geom`, pure function
`ballistics_range(v0, ang_deg)`) and `/app/sources/drive.f90` (a `drive`
program that reads two reals `v0 ang` from stdin and prints
`ballistics_range(v0, ang)` with `(F12.3)`).

The lab ships a build file `/app/sources/Makefile.fk81` whose frontend
variable is `FC = g95` — **`g95` is not installed**.  The two `.f90` sources
are locked and must **not** be edited.  Create `/app/Makefile`: rewrite the
provided build file to drive **`gfortran`** instead (a drop-in change of the
frontend variable), keeping the module-compiled-before-program ordering, and
build `/app/main`.

`gfortran` compiles the module source *before* the program that `USE`s it:

```
make -f /app/Makefile        # builds /app/main in /app
echo "30 45" | /app/main     # prints the range, e.g.  91.774
```

The verifier re-runs the build (`make -f /app/Makefile`, forcing a full
rebuild with `make -B` so the `gfortran` frontend must actually appear in the
compile log) and also checks the Makefile text itself drives the `gfortran`
frontend; then it runs `/app/main` on further `v0 ang` pairs, checking the
printed range matches
`v0^2 * sin(2*ang) / g` with `g = 9.80665`.

## 3. Polyglot source — `/app/poly.c`

Write **one** source file at `/app/poly.c` that compiles error-free **both** with
`gcc` *and* with `g++` from the same bytes, and whose behavior differs based on
the toolchain.  The verifier does:

```
gcc  -o /tmp/pc   /app/poly.c && /tmp/pc    # must print  poly:c=0
g++  -o /tmp/pcpp /app/poly.c && /tmp/pcpp  # must print  poly:c=1
```

A clean way is to select an active branch with the predefined macro
`__cplusplus` (defined only by the C++ compiler).  Build it from source with
both toolchains and confirm both outputs before you finish.

## 4. Particle toolkit CLI + release harness — `/app/app`

Source: `/app/sources/kite_app.c` (complete and correct — build it with
`gcc -O2 -o /app/app /app/sources/kite_app.c`).  It implements **three modes**:

### 4a. Recon CLI (particle reconstruction)

```
/app/app -n <COUNT> -p <POSFILE> -s <SUMFILE> -t <THREADS>
```

* `-n`   particle count `1..5000` (required)
* `-p`   path of the **position output file** (required)
* `-s`   path of the **summary output file** (required)
* `-t`   worker-thread hint `1..16` (required)

**Position file** — first line must be exactly `# i,x,y,z,m`, then one line per
particle `i` from `0..n-1` of the form `i,x,y,z,m` where `m` is the mass in
`{3,4,5,6}`; coordinates are integers in `0..999999`.  Values are
deterministic and independent of `-t` (documented; `-t` only selects a worker
budget, never the values).

**Summary file** — exactly these lines (no trailing junk):

```
count=<n>
mass_sum=<sum of m>
total_x=<sum of x>
total_y=<sum of y>
total_z=<sum of z>
extent_x=<max_x-min_x>
extent_y=<max_y-min_y>
extent_z=<max_z-min_z>
```

**stdout** — exactly one line:

```
particles=<n> sum_x=<total x> sum_y=<total y> threads=<t>
```

### 4b. Release harness mode (autoregressive sampler)

```
/app/app sample <LEN> <SEED>
/app/app key   <SEED>
```

* `app sample <LEN> <SEED>` prints `LEN` lowercase letters (`a`..`z`) produced
  by a greedy autoregressive arg-max sampler.  This is invoked **through the
  external launcher** `/app/launcher.py` (a Python reference that implements
  the sampler independently):
  `python3 /app/launcher.py sample <LEN> <SEED>` runs `./app sample ...`,
  compares the bytes to the reference, and prints `LAUNCH_OK <LEN> <SEED>` on
  a match (or `LAUNCH_FAIL ...`).  The launcher must report `LAUNCH_OK` for
  every hidden `(LEN, SEED)` it is given.  If your build differs from the
  reference (wrong wrap-around arithmetic, a negative modulo, a different
  alphabet), the launcher reports `LAUNCH_FAIL`.
* `app key <SEED>` prints the **8-letter activation code** for that seed (it
  equals `app sample 8 <SEED>`).

The sampler algorithm is fully specified by the provided Python reference in
`/app/launcher.py` — make sure the C port reproduces it bit-for-bit (32-bit
wraparound LCG `s = (s*1664525 + 1013904223) & 0xFFFFFFFF`, and a non-negative
modulo so the C `%` matches Python's `%`; the C source already does this).

### 4c. Release activation code file — `/app/key.txt`

The lab lists its **official release seeds** in `/app/sources/key_seeds.txt`
(one seed per line).  Produce `/app/key.txt` with one line per seed:

```
<seed>=<8-letter activation code>
```

You must derive each code from the sampler itself (e.g. run `/app/app key
<seed>`), **not** invent values.  The verifier **recompiles
`/app/sources/kite_app.c` from source with the system `gcc` into a fresh
binary and checks the codes you recorded still match that clean rebuild** —
so the codes must be genuine outputs of the algorithm, not values accepted
only by a tampered binary.  It also verifies the shipped `/app/app` binary
behaves identically to the rebuilt-from-source binary on a few extra seeds.

## 5. Metacircular evaluator — `/app/scheme.py`

Write `/app/scheme.py`: a **metacircular evaluator** for the documented
"Scheme-Lite" dialect, implementing environment analysis, closures with
capture, and `eval`/`apply`.  (No third-party anything; it must be a single
self-contained Python file you run as `python3 /app/scheme.py`.)

**Invocation contract:** `python3 /app/scheme.py < program` reads the whole
program from stdin, parses it as a stream of top-level forms, evaluates each in
the shared global environment, and prints on **its own line** the Scheme
textual value of every top-level form **except definitions** (`define` prints
nothing).  Scheme textual values: integers as decimal; booleans as `#t` / `#f`;
a symbol as its name; a list as `(a b c)` (recursive, space-separated);
a closure as `#<procedure>`.  Nothing else is printed.

**Dialect (support at least):**
* self-evaluating integers, `#t`, `#f`;
* `(quote x)` and the `'x` shorthand;
* `(define name expr)` and the sugared `(define (f p1 p2 ...) body...)`;
* `(lambda (params) body...)` — captures the defining environment (closures);
* `(if cond then else)` (else optional; false/empty is falsy);
* `(begin e...)`, `(let ((x v)...) body...)`;
* primitives `+ - * = < >  car cdr cons list  eq? null? number? boolean? pair? symbol? not`
  (arithmetic is integer-only; `cdr` of a one-element list returns the empty list);
* `(apply proc arglist)` and `(eval expr)` — evaluate `expr` in the global env.

The verifier runs your `/app/scheme.py` on hidden Scheme-Lite programs and
compares the exact printed lines against the reference semantics.

---

## Deliverables checklist

```
/app/game.mips      # MIPS ELF built from /app/sources/hop.c  (CROSS-compiled)
/app/main           # gfortran build of geom.f90 + drive.f90
/app/Makefile       # rewritten to FC = gfortran (sources untouched)
/app/poly.c         # compiles under gcc AND g++; prints poly:c=0 / poly:c=1
/app/app            # gcc -O2 build of /app/sources/kite_app.c
/app/key.txt        # <seed>=<code> for every seed in /app/sources/key_seeds.txt
/app/scheme.py      # metacircular Scheme-Lite evaluator
```

The hidden verifier exercises every one of these: it runs the MIPS ELF under
`qemu-mipsel-static`, re-runs the gfortran build and `main`, recompiles
`poly.c` with both toolchains, drives `app` in recon mode and through the
lazy launcher, recompiles the app from source to cross-check `key.txt` and the
shipped binary, and evaluates hidden Scheme-Lite programs.