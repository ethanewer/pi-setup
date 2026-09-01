# dune-hearth — hearth-signal build project

## Goal

Author a small C/C++ build project called `dune-hearth` from scratch and leave a
working build in `/app`. You must:

1. Write a CMake project (`/app/CMakeLists.txt`) that configures and compiles the
   serial executable `prog`.
2. Write a single **Makefile** (`/app/Makefile`) whose default target builds all
   **three** executables — serial, OpenMP, and MPI — into `/app/bin/` with the
   correct toolchains and link flags.
3. Write a build orchestrator `/app/build.sh`.
4. Build everything, and make `prog` invocable **bare (by name) from any
   directory** through the shell `PATH`.

## Contract (exact paths / formats / behaviors)

### The `prog` program (serial CLI)

`/app/bin/prog` is a CLI that reads **two numeric data files** and prints one
numeric result to stdout:

```
prog <weights-path> <sample-path>
```

- **Argument order is fixed:** the *weights* file must be argument 1 and the
  *sample* file must be argument 2. Swapping them must change the result for
  typical inputs (the program must not auto-detect; it reads order literally).
- Each file contains **one numeric token per line** (see parsing below).
- **Parsing rule (apply exactly):**
  - A token is valid iff the trim-able line is a single real number with no
    leftover characters — i.e. everything on the line after optional leading
    whitespace is a number (`[0-9]`, optional `+-`, optional `.`, optional
    `e`/`E` exponent), followed by optional trailing whitespace.
  - Allow integer and decimal forms and scientific notation (e.g. `12`, `-3.5`,
    `2.5e3`, `7.`).
  - **Blank lines are ignored.** Lines containing any non-numeric text (e.g.
    `junk`, `1.2 3.4`, `"5"`) are ignored entirely (they contribute nothing and
    do not shift indices).
- Let `w = [w0, w1, ...]` be the valid weights (in file order) and `s = [s0,
  s1, ...]` the valid sample values (in file order). Let `n = min(len(w),
  len(s))`.
- **Result** `r = sum_{i=0}^{n-1} w[i] * s[i]`.
- Print `r` to **stdout as a single line** formatted to exactly **3 decimal
  places** (e.g. `32.000`, `30.500`). Then exit with status `0`.
- If `n == 0` (all-empty or mismatched-empty inputs) print `0.000` and exit `0`.
- If invoked with any number of arguments other than exactly 2, print the usage
  line to **stderr** (`usage: prog <weights-path> <sample-path>`) and exit `1`.
- If a given input file does not exist or cannot be opened, print a brief error
  to **stderr** and exit `1` (no stdout result).

### The project layout (author these inside `/app`)

```
/app/
  CMakeLists.txt        # cmake project; builds the serial `prog` executable
  Makefile              # default target builds prog, prog_omp, prog_mpi
  build.sh              # orchestrator: builds, installs to PATH, tars source
  src/
    prog.c              # the serial program (also the OpenMP source)
    mpi_main.cpp        # a valid MPI program (uses MPI_Init/Rank/Finalize)
  bin/                  # containing the built binaries (bin/prog, bin/prog_omp, bin/prog_mpi)
  dist/                 # (created by build.sh) dune-hearth-src.tar.zst
```

### Makefile contract

- `make` (default target) must compile **all three** binaries:
  - `/app/bin/prog`       — compiled with `cc`/`gcc` (serial; **no** `-fopenmp`,
    **no** MPI libraries).
  - `/app/bin/prog_omp`   — compiled with `-fopenmp` so it dynamically links the
    OpenMP runtime (`libgomp`).
  - `/app/bin/prog_mpi`   — compiled with **`mpicxx`** from the MPI source (links
    `libmpi`). OpenMPI (`mpicxx`, `mpicc`, `mpirun`) is installed and on PATH.
- `make clean` removes the build binaries.
- `make selftest` runs `bin/prog` on the built-in sample data:
  - weights file `2` then `3`; sample file `5` then `7` → expected `31.000`.
  - It must print exactly `SENTINEL=dune-hearth-ok` to stdout and exit `0` on a
    passing check; on any failure it must exit nonzero and must **not** print the
    success sentinel. Do not modify the sentinel string.
  - If `bin/prog` is missing it should rebuild as needed.

### CMake contract

`cmake -S /app -B <builddir>` must configure and `cmake --build <builddir>`
must compile a working serial `prog` executable (`<builddir>/prog`) with the same
CLI behavior described above.

### PATH install

`build.sh` must make the serial `prog` invocable **bare (by name) on the shell PATH**:
install a copy of `/app/bin/prog` at `/usr/local/bin/prog` (mode `0755`), so that
`prog <weights> <sample>` works from any working directory and `command -v prog`
resolves to `/usr/local/bin/prog`.

### build.sh contract

Running `bash /app/build.sh` must be **idempotent** and must, in order:
1. clean and rebuild the three binaries;
2. install the serial `prog` onto the PATH (`/usr/local/bin/prog`);
3. produce a **zstd-compressed GNU tar** archive at
   `/app/dist/dune-hearth-src.tar.zst` containing at least the files
   `CMakeLists.txt`, `Makefile`, `build.sh`, and the whole `src/` tree, using
   GNU tar with the `zstd` compressor (so `zstd -t` and `tar --zstd -tf` both
   succeed and the member list contains `CMakeLists.txt` and `src/prog.c`).

Run `bash /app/build.sh` as part of your work so the deliverables (`/app/bin/
prog`, `/app/Makefile`, `/app/build.sh`) and the PATH install are present when
you finish.

## Constraints

- No external/shipped libraries: `prog` (the cooked serial binary) must need no
  shared libraries beyond the C standard runtime (libc/libm/libgcc). Its `ldd`
  output must not list e.g. `libmpi`, `libgomp`, or random third-party shared
  objects. (The OpenMP and MPI binaries legitimately pull `libgomp`/`libmpi`.)
- Build only with the packages already installed (gcc, g++, make, cmake, OpenMPI,
  zstd, tar, python3); do not use `sudo`/`systemd`.
- Keep all deliverables at the exact paths above.

## Definition of done

When all of the following hold, your submission is complete:
- `make -C /app clean && make -C /app all` produces `/app/bin/prog`,
  `/app/bin/prog_omp`, `/app/bin/prog_mpi`.
- `link flags are right`: `prog_omp` → `libgomp`; `prog_mpi` → `libmpi`;
  `prog` → no external runtime libs.
- `cmake` satisfactorily builds `prog`.
- `make -C /app selftest` prints `SENTINEL=dune-hearth-ok` with exit `0`.
- `prog` runs correctly on any hidden weights/sample files obeying the parsing
  rule above (including empty, junk-laden, mismatched-length and
  missing-file cases), always emitting the weights-then-sample result.
- `bash /app/build.sh` builds, installs `prog` on PATH, and produces the zstd
  GNU tar at `/app/dist/dune-hearth-src.tar.zst`.