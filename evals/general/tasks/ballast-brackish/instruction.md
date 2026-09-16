# ballast-brackish

You are working inside a real open-source codebase: the **Z3** theorem
prover / SMT solver (`Z3Prover/z3`), checked out at a pinned commit in
`/app/src` (the working tree starts clean). There is a soundness bug in this
tree: for some satisfiable formulas about integer sequences it prints
`unsat` — a wrong verdict. Your job is to find it, fix it in the working
tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Ubuntu 24.04 with `g++` (GCC 13), `cmake`, `make`, `git` installed.
- The tree at `/app/src` is a shallow one-commit clone (detached `HEAD` at a
  pinned 40-hex commit). Do **not** commit, fetch, or otherwise modify
  `.git`.
- A configured Release `cmake` build already exists at `/app/src/build`,
  built at this exact commit — `build/z3` (the solver binary) and
  `build/test-z3` (the project's own test harness) are present. Rebuild
  **incrementally**: `cmake --build build --target shell` recompiles only
  what you changed. Do not delete or re-configure `build/` from scratch: a
  full build is far too slow on the single vCPU this container provides.
- **There is no network** in this container. Everything needed is baked in.
- `cpus = 1`: one vCPU. Do not launch parallel builds.

## The bug (user-visible symptom)

For some satisfiable `(Seq Int)` formulas, Z3 prints `unsat` instead of
`sat`. The pattern: a sequence variable is constrained to equal a
`seq.extract` (a.k.a. `seq.substr`) slice of a sequence concatenation whose
elements include an if-then-else term selecting between integer elements,
and — in the case below — whose first element is the length of the very
sequence being solved. That self-referential first element sits *before*
the extracted region and should not matter at all.

Reproduce it:

```bash
cat > /tmp/A_seq_extract.smt2 <<'EOF'
(declare-const x Bool)
(declare-const y (Seq Int))
(assert (= y (seq.extract (seq.++ (seq.++ (seq.unit (seq.len y)) (seq.unit (ite x 0 1))) (seq.++ (seq.unit 1) (seq.unit 0))) 2 2)))
(check-sat)
EOF
cd /app/src && ./build/z3 /tmp/A_seq_extract.smt2
```

On this tree the command prints `unsat`. That is **wrong**: the extracted
slice starts after the first two elements, so the formula is satisfiable —
e.g. `x = true`, `y = [1, 0]` (take `(ite x 0 1)` as `1`; then the
concatenation is `[len(y), 1, 1, 0]`, `seq.extract` from offset 2 of length 2
is `[1, 0]`, which equals `y`). The correct verdict is `sat` with a model.

## Requirements

1. Fix the tree so that `./build/z3 /tmp/A_seq_extract.smt2` prints `sat`.
   Do not stop there: the same underlying defect is reachable from other,
   differently-shaped inputs (different offsets, lengths, branch values, and
   groupings of the concatenation produce the same wrong `unsat`; see
   Grading). Fix the mechanism, not just this one input.
2. Keep the solver correct in the other direction too: genuinely
   unsatisfiable sequence formulas must still come out `unsat`, and the
   project's own sequence-rewriter tests must stay green.
3. The graded tree must be byte-identical to the pinned commit except for
   the **minimal set of source files the fix needs** (a correct fix here
   changes exactly **one** C++ source file). Do not add, move, delete,
   rename or reformat any file; delete scratch files you created before you
   finish; make no commits; do not modify any test file, build script, CMake
   file, or metadata file. The grader diffs every file's bytes against the
   pinned commit, so cosmetic side-changes also fail.
4. Rebuild after your fix so that `/app/src/build/z3` reflects it (the
   verifier also rebuilds from the tree itself, so the source is what
   matters).

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above (scratch files in `/tmp`, never
   inside `/app/src`).
2. **Localise**: the symptom lives in sequence rewriting — study how Z3
   rewrites `seq.extract` / `seq.at` / `seq.nth_i` over concatenations
   before the SMT solver sees them. Use the source tree (`src/`), `grep`, and
   Z3's own tracing options. Temporary instrumentation edits are fine while
   investigating, but the final tree must contain only the fix.
3. **Fix** the smallest possible way in the one source file, rebuild with
   `cmake --build build --target shell`, and confirm the reproduction prints
   `sat`.
4. **Prove nothing else broke**: run `./build/test-z3 seq_rewriter` — the
   project's own sequence-rewriter test module (already compiled at this
   commit; it must still link and pass after your change). Also confirm a
   genuinely unsatisfiable sequence formula still reports `unsat`.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the working
  tree contains **no** untracked files, and that every tracked file except
  the single source file your fix touches is byte-identical to that commit
  (modified, added or deleted files anywhere else fail);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it is not in
  this tree) into `src/test/seq_rewriter.cpp`, rebuild `test-z3` offline,
  and run `./build/test-z3 seq_rewriter`: **all** tests in the module must
  pass, including the pre-existing sequence-rewriter tests, so a fix that
  breaks ordinary rewriting fails;
- run `/app/src/build/z3` directly on **hidden SMT2 cases** — other inputs
  that reach the same broken code path — and require the exact verdict:
  `sat` where the bug caused a spurious `unsat`, and `unsat` on a genuinely
  inconsistent formula.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.