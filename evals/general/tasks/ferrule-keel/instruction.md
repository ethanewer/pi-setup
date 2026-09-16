# Build a real C compiler from source, use it, and explain the one place it disagrees with gcc

## Context

`/app/src` is a shallow git clone of the upstream **TinyCC/tinycc** repository,
pinned to tag `release_0_9_27` (commit `d348a9a51d32cece842b7885d27a411436d7887b`).
It is the C compiler *tcc* in source form, complete with its own `configure`
script and `Makefile`, its own standard headers under `/app/src/include`, its
own C test suite under `/app/src/tests/tests2`, and its own manual
`/app/src/tcc-doc.texi`.

The image contains the toolchain you need (gcc 13.3, make, git, libc headers)
and **nothing else compiler-like**: there is no prebuilt tcc anywhere in the
image and no network access, so the only tcc that can exist here is one you
build from `/app/src`.

## Task

1. Build the compiler from `/app/src` using *its own* build system:
   `./configure && make && make install`. Install it with
   **`--prefix=/app/tccinst`** so the installed compiler lands at
   `/app/tccinst/bin/tcc` (a directory under `/app`, which is writable by your
   user). Do not modify the compiler's source files; build products inside
   `/app/src` (`config.mak`, `config.h`, `*.o`, the `tcc` binary, the `tests2`
   artifacts) are fine and expected.

2. `/app/programs/` contains five C programs: `hello.c`, `fib.c`, `strings.c`,
   `structs.c` and `complex.c`. Do **not** modify them. Compile and run each
   one with **your** built compiler, and record the stdout of every one that
   compiles into `/app/outputs/<name>.out` (for example
   `/app/outputs/fib.out`). The files must contain the program's stdout
   byte-exactly, nothing else.

   Not every program may compile with your compiler. For any program your
   compiler rejects, do the following instead:
   - capture the compiler's stderr into `/app/outputs/<name>.err` (exactly the
     stderr, nothing else);
   - compile and run the same source with the system `gcc`, and record that
     stdout into `/app/outputs/<name>.gcc.out`.

   The rest of your task depends on noticing the asymmetry, so compare the two
   compilers honestly.

3. Write `/app/diagnosis.md` (plain text, at least one full paragraph) that
   answers these questions precisely:
   - which of the five programs does tcc handle differently from gcc, and in
     what way;
   - which standard C(-99) language feature is responsible, and why tcc cannot
     process it (quote tcc's first error line literally);
   - cite the section of `/app/src/tcc-doc.texi` that documents this missing
     feature.

Do not install anything, do not fetch anything, and do not rename or annotate
the programs: the delivered output files must be reproducible byte-exactly by
whoever verifies them.

## What you must deliver

- `/app/tccinst/bin/tcc` — the compiler you built and installed
- `/app/outputs/hello.out`, `/app/outputs/fib.out`,
  `/app/outputs/strings.out`, `/app/outputs/structs.out` — stdout of your
  compiler on the four programs that must build
- `/app/outputs/complex.err` — your compiler's stderr for the program it
  cannot build
- `/app/outputs/complex.gcc.out` — the gcc stdout for that same program
- `/app/diagnosis.md` — the explanation above

The verifier recompiles `/app/programs/*.c` with **your** `/app/tccinst/bin/tcc`
(and with `gcc` where your compiler cannot), compares the outputs byte-exactly,
checks your diagnosis, and runs the upstream project's own `tests2` test suite
against your build.