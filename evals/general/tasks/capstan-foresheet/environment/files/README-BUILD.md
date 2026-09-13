# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (Z3Prover/z3, the SMT
solver) checked out at a pinned, shallow (single) commit. Everything needed to
build and test it offline is baked into this image:

- Toolchain on `PATH`: `g++` (GCC 13), `cmake` (3.28), `make`, `git`.
- A warm Release build at `/app/src/build`, configured with the project's own
  recipe (`cmake -S . -B build -DCMAKE_BUILD_TYPE=Release`):
  - the solver binary at `/app/src/build/z3` (the `shell` target),
  - the project's unit-test harness at `/app/src/build/test-z3` (target
    `test-z3`, which is excluded from the default build; the image built it).
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
about half a minute on this machine. Individual modules can be run by name.

Do not modify the `.git` directory (its history is intentionally shallow and
the working tree must stay on the pinned commit), and do not commit, fetch or
pull. Write scratch files under `/tmp`, never inside the repository.