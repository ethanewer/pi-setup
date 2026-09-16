# corvette-towpath

You are working inside a real open-source codebase: **Z3**
(`Z3Prover/z3`), the SMT solver from Microsoft, checked out at a pinned
commit in `/app/src` (the working tree starts clean, at the buggy commit).
There is a bug in this tree's floating-point reasoning. Your job is to write
a reproduction of it, find it, fix it in the working tree, and prove the fix
with the project's own test tooling. You are deliberately **not** told which
file or function to change: localising the bug is part of the task.

## Environment

- Build toolchain is installed and on `PATH`: `g++` (GCC 13), `cmake`,
  `make`, `git`.
- There is no guaranteed network in this container: everything needed is
  baked in, and nothing may be downloaded. A warm Release build lives at
  `/app/src/build` (see `/app/README-BUILD.md`), containing the solver binary
  `/app/src/build/z3` and the project's unit test harness
  `/app/src/build/test-z3`, compiled at this same pinned commit. Any
  `cmake`, `make` or `z3` command you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, pull, or otherwise modify `.git`.
- Read `/app/README-BUILD.md` before doing anything else.

## The bug (user-visible symptom)

A user reports:

> I'm checking a fused multiply-add with Z3. I pin the operands to concrete
> bit patterns — binary16 (`(_ FloatingPoint 5 11)`), 16 bits: 1 sign,
> 5 exponent, 10 significand — and pin the rounding mode to
> round-to-nearest-even (`RNE`). The formula asks whether the IEEE 754
> encoding of the fused multiply-add is not the value it must be. Since the
> operands fully determine the operation, the formula is ground and has
> exactly one correct answer. I computed the true IEEE 754 result
> independently of Z3, and my formula has Z3 assert that the result
> encoding differs from that true value. Z3 answers `sat` and produces a
> model — the encoding that the model's value converts to differs from the
> true IEEE 754 encoding by one unit in the last place. The same formula is
> `unsat` in every other solver I tried, and in Z3 too once I patched it.

Concretely, the user's two half-precision operands were

- `x` — the `(_ FloatingPoint 5 11)` value of bit pattern `#b1000001111000111`,
- `y` — the `(_ FloatingPoint 5 11)` value of bit pattern `#b0011110111000000`,

built with `((_ to_fp 5 11) <bv>)`, and the operation is
`(fp.fma RNE x y x)` (addend equal to `x`).

What the symptom is **not**: `fma` is deterministic, so the wrong encoding is
a *computational* defect in how the solver evaluates the operation, not a
random or search-dependent artefact. The solver lowers floating-point
operations to bit-vector arithmetic; that conversion machinery
(`fpa2bv`) is where the value gets its low bit wrong. Depending on how the
solver is asked to check the formula, the defective conversion path may or
may not be exercised, so expect to have to steer the check onto it.

## Your task

1. **Write a reproduction first.** Create `/app/reproduce.sh`:
   - executable (`chmod +x`), runs with no arguments and no network;
   - uses the solver binary named by the environment variable `Z3_BIN`; if
     that variable is unset or empty it defaults to `/app/src/build/z3`, and
     the script must actually invoke `$Z3_BIN` on a query file it writes
     itself to a temporary location (e.g. under `/tmp`);
   - prints to stdout **exactly one line**: the solver's verdict for its
     query — either `sat` or `unsat` — and nothing else;
   - the query has the shape the user described: pin the rounding mode and
     every operand with concrete bit-vector constants, then assert that the
     IEEE encoding of the fused multiply-add differs from the value you
     compute yourself, by the IEEE 754 rules, independently of Z3. Such a
     query is ground: its correct answer is `unsat` when the operation is
     computed correctly, and the defective conversion answers `sat`.

   On the current (unfixed) tree, `Z3_BIN=/app/src/build/z3 /app/reproduce.sh`
   must print `sat`. **Verify that before you fix anything** — a
   reproduction that does not fail on the current tree is not a reproduction
   of this bug.

2. **Fix the correctness defect** in the source tree. Find the root cause in
   the C++ sources under `/app/src/src`, understand why the computed encoding
   can come out one ulp off for the affected inputs, and change it with the
   smallest possible edit. Do not special-case the reproduction's input
   values, and do not add a workaround in the solver driver or the SMT2
   front end: the mechanism itself must be fixed. Then rebuild incrementally
   and offline:

   ```bash
   cd /app/src
   cmake --build build --target shell -j1     # rebuild build/z3
   cmake --build build --target test-z3 -j1   # rebuild the unit-test harness
   ```

   After the fix, `/app/reproduce.sh` (default binary) must print `unsat`,
   and the project's own unit test suite must still pass.

3. **Prove nothing else broke.** Run the project's own unit tests:
   `/app/src/build/test-z3 -a` must pass in full (the whole suite runs in
   under a minute even at 1 CPU). You may also run individual modules by
   name, e.g. `/app/src/build/test-z3 smt_context`.

4. **Write `/app/summary.md`** — a non-empty change summary: what the bug
   was, what you changed, and how you verified it.

## Constraints

- The graded tree must be identical to the pinned commit except for the
  **single source file where the bug lives**. Do not add, move, delete,
  rename or reformat any file; make no commits; do not modify anything under
  `src/test/`, any `CMakeLists.txt`, any metadata file, or `.git`. Scratch
  files you create to investigate go in `/tmp` and must not be placed inside
  `/app/src`.
- Do not delete or recreate `/app/src/build` (keep the warm build; every
  rebuild must be incremental and offline).
- The grader compares every tracked file's bytes against the pinned commit's
  own blobs (via git's own diff, which accounts for the repository's
  checkout-time line-ending normalization) and rejects any change outside the
  one fixed source file, so cosmetic side-changes also fail.

## Deliverables

1. `/app/reproduce.sh` — the reproduction described above,
2. `/app/src` — the working tree with your fix applied,
3. `/app/summary.md` — the change summary.

## Grading

The verifier will, on your final tree:

- assert provenance: `HEAD` is still the pinned parent commit; every tracked
  file except the single fixed source file is byte-identical to that commit
  (git-aware); there are no untracked non-ignored files; `/app/summary.md`
  exists and is non-empty;
- run your `/app/reproduce.sh` with the verifier's copy of the **pre-fix**
  solver binary and require it to print `sat` (this proves the reproduction
  genuinely fails on the unpatched tree);
- rebuild the solver and the test harness from your tree, offline;
- run your `/app/reproduce.sh` against the rebuilt solver and require it to
  print `unsat`;
- plant the project's **own regression test** for this bug — the fix-commit
  version of the test file `smt_context.cpp` is baked into the image at
  `/opt/golden` (this tree, being the parent commit, does not contain it) —
  rebuild the harness, run module `smt_context` and require it to pass, then
  run the project's entire remaining unit suite (`test-z3 -a`) and require 0
  failed;
- run the rebuilt solver on **hidden SMT cases** — other half-precision
  `fma` operand pairs (bit patterns and expected encodings that differ from
  every case above) that reach the same broken path — each must print
  exactly `unsat` and exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.