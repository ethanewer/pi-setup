# ballast-brackish build notes

This image ships the real Z3Prover/z3 source tree at `/app/src`, checked out
at a pinned commit (detached HEAD). A warm Release cmake build is in
`/app/src/build/`:

- `/app/src/build/z3`      — the solver binary (target `shell`)
- `/app/src/build/test-z3` — the project's own test harness (target `test-z3`)

No network is available in the trial container. Use the warm build and
rebuild incrementally after changing sources:

```bash
cd /app/src
cmake --build build --target shell      # recompile changed files, relink
./build/z3 /path/to/formula.smt2        # print the verdict

# project's own sequence-rewriter tests
./build/test-z3 seq_rewriter
```

Do not delete or re-configure `build/` from scratch; a full build at one
vCPU is far too slow. The `.git` directory must not be modified.