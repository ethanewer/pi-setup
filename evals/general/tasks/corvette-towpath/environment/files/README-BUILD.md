# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (Z3Prover/z3, the SMT
solver) checked out at a pinned, shallow (single) commit. Everything needed to
build and test it offline is baked into this image:

- Toolchain on `PATH`: `g++` (GCC 13), `cmake` (3.28), `make`, `git`.
- A warm Release build at `/app/src/build`, configured with the project's own
  recipe (`cmake -S . -B build -DCMAKE_BUILD_TYPE=Release`):
  - the solver binary at `/app/src/build/z3` (the `shell` target),
  - the project's unit-test harness at `/app/src/build/test-z3` (target
    `test-z3`).
  All build artifacts are up to date at the pinned commit, so any rebuild is
  strictly incremental and completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds (`-j1` is implied by
  the container, but say it explicitly if you pass jobs).

Common commands (all offline):

    cd /app/src
    cmake --build build --target shell -j1     # incremental rebuild of build/z3
    cmake --build build --target test-z3 -j1   # incremental rebuild of build/test-z3
    ./build/z3 <file>.smt2                     # run a query file with the solver
    ./build/test-z3 -a                         # project's own full unit-test suite
    ./build/test-z3 <name>                     # run exactly one unit test module

The project's own test suite is run with `test-z3`; running all of it takes
about half a minute on this machine (well under a minute at 1 CPU).
Individual modules can be run by name (for example `test-z3 smt_context`).

Do not modify the `.git` directory (its history is intentionally shallow and
unrelated to the upstream project), do not delete or recreate `/app/src/build`
(rebuilt incrementally only), and keep any scratch files you create in `/tmp`.

The image ships two root-owned read-only inputs used by the grader, not by
you: `/opt/pre-fix/z3`, a pristine copy of this tree's solver binary as it
was built before any fix, and `/opt/golden/`, the project's own regression
test for the floating-point bug (as added by the upstream fix commit, which
this tree does not contain). You do not need them.