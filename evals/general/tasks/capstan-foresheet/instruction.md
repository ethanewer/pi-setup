# capstan-foresheet

You are working inside a real open-source codebase: **Z3**
(`Z3Prover/z3`), the SMT solver from Microsoft, checked out at a pinned
commit in `/app/src` (the working tree starts clean). There is a bug in this
tree's floating-point reasoning. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Build toolchain is installed and on `PATH`: `g++` (GCC 13), `cmake`,
  `make`, `git`.
- **There is no network** in this container. Everything needed is baked in:
  a warm Release build at `/app/src/build` (see `/app/README-BUILD.md`),
  containing the solver binary `/app/src/build/z3` and the project's unit
  test harness `/app/src/build/test-z3`, compiled at this same pinned commit.
  Any `cmake`, `make` or `z3` command you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, pull, or otherwise modify `.git`.

## The bug (user-visible symptom)

Z3 computes an incorrect IEEE 754 remainder for the floating-point operation
`fp.rem` **whenever the divisor is a subnormal (denormalized) number** — a
floating-point value whose exponent field is all zero bits. The operands
below are fully pinned down by their bit patterns, so `fp.rem x y` has one
deterministic, exactly-specifiable value; asking Z3 whether that value is
*not* the correct one must answer `unsat`. On this tree the solver instead
answers `sat`, and its model for `(fp.rem x y)` is `-0.0` (bit pattern
`#x8000`), while the true IEEE 754 remainder of the two operands is the
positive subnormal number with bit pattern `#x000a`.

Reproduce it. Put this exact query in a file, e.g. `/tmp/B_fp_rem.smt2`:

```
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b1110100000101010)))
(assert (= y ((_ to_fp 5 11) #b1000000000010101)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x000a)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
```

and run

```bash
/app/src/build/z3 /tmp/B_fp_rem.smt2
```

On the buggy tree this prints `sat`. The correct answer is `unsat`: both
operands are pinned, and the solver's own conversion pipeline must be able
to determine that the IEEE encoding of `(fp.rem x y)` is exactly `#x000a`.
(The two operands are concrete, so no search is involved: the pipeline
deterministically computes one bit-vector encoding for the remainder, and
on this tree that encoding is wrong — it computes the encoding of negative
zero, `#x8000`, instead of the true remainder `#x000a` — so the assertion
`(not (= ... #x000a))` is satisfiable and the answer comes back `sat`.)

You must use the check-sat-using pipeline shown above with exactly this
tactic sequence (`fpa2bv simplify bit-blast smt`) — that is the code path
that exhibits the bug; plain `(check-sat)` takes a different route and may
not show it.

The defect is not specific to that one query. Any `fp.rem` whose divisor is
subnormal and whose exponent relationship to the dividend is extreme enough
(roughly: the dividend's exponent is large while the subnormal divisor is
deeply denormalized) hits the same broken machinery. Two more half-precision
pairs on the same path, with their exact expected 16-bit IEEE encodings:

```bash
cat > /tmp/v1.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b0101100000000001)))
(assert (= y ((_ to_fp 5 11) #b0000000000000011)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x0001)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
/app/src/build/z3 /tmp/v1.smt2      # sat on the buggy tree, must be unsat

cat > /tmp/v2.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b1111010000000000)))
(assert (= y ((_ to_fp 5 11) #b1000000001000001)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x8004)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
/app/src/build/z3 /tmp/v2.smt2      # sat on the buggy tree, must be unsat
```

The IEEE 754 remainder `r = x rem y` is defined by `r = x − n·y` where `n`
is the integer nearest to `x/y` (ties to even). Verifying one of these
values by hand — e.g. `n` as the nearest integer, then re-checking that the
asserted 16-bit encoding matches the correctly rounded remainder — is a
useful cross-check of your own understanding before you start.

## Requirements

1. Fix the tree so that `fp.rem` with a subnormal divisor returns the
   correct IEEE 754 remainder. All three queries above must print `unsat`
   (rebuilt binary `/app/src/build/z3`).
2. The symptom above is the visible part: fix the **mechanism**, not these
   inputs. The root cause is in how the `fpa2bv` conversion machinery turns
   `fp.rem` into bit-vector arithmetic: it sizes some bit-vector
   significand arithmetic against the maximum possible exponent difference
   *between normal-or-subnormal operands in the worst case of the exponent
   range*, which silently under-estimates the case where the divisor is
   subnormal, so high-order bits of the dividend are shifted out before the
   remainder is computed and the computed value is garbage (here, `-0.0`).
   The correct computation must widen the significands enough to cover a
   subnormal divisor too. Do not special-case the reproduction, and do not
   merely add a workaround in the solver driver or the smt2 front end.
3. Everything else must keep working exactly as before: `fp.rem` on normal
   divisors, the other floating-point operations, and the rest of the
   solver. The project's own unit test suite must stay green
   (`/app/src/build/test-z3 -a`; see `/app/README-BUILD.md`).
4. The graded tree must be identical to the pinned commit except for the
   **single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `src/test/`, any `CMakeLists.txt`, or any metadata file. The grader
   verifies every tracked file's content against the pinned commit's own
   blobs (via git's own diff, which accounts for the repository's
   checkout-time line-ending normalization) and rejects any change outside
   that one file, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src/build/z3` and the queries above (scratch
   files in `/tmp`, never inside `/app/src`). Confirm the shape of the
   failure: create a few other half-precision `fp.rem` queries with a
   subnormal divisor (`((_ to_fp 5 11) #b00000...` in the exponent field) —
   all answer `sat` where they must answer `unsat`, while `fp.rem` with a
   *normal* divisor (exponent field nonzero) answers correctly.
2. **Localise** the bug: `fp.rem`'s SMT-LIB semantics were, as the tactic
   name hints, reduced to bit-vector arithmetic. Find the conversion code
   that compiles `fp.rem` down to bit-vectors — in `src/ast/` — and read
   how it sizes the significand arithmetic and the shift amounts that
   align the two operands' exponents. Understand what happens to the
   *normalized* exponent difference when the divisor is subnormal, and why
   the sizing under-covers it, before you patch.
3. **Fix** with the smallest possible change in that one file. Then rebuild
   incrementally (`cmake --build build --target shell -j1`) and confirm that
   every query from step 1 now prints `unsat` (and that `fp.rem` cases that
   were already correct still are).
4. **Prove nothing else broke**: rebuild the project's unit test harness
   (`cmake --build build --target test-z3 -j1`) and run the project's own
   suite: `/app/src/build/test-z3 -a` must pass in full (it takes about
   half a minute at 1 CPU). You may also run individual modules by name,
   e.g. `/app/src/build/test-z3 bit_vector`.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit and that every
  tracked file except the single source file the bug lives in is identical
  to that commit (any other modification, added file or untracked scratch
  file fails);
- require `/app/summary.md` to exist and be non-empty;
- rebuild the solver binary and the project's test harness from your tree,
  offline;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree; the verifier performs the same two one-line edits to
  `src/test/main.cpp` and `src/test/CMakeLists.txt` that upstream's fix
  commit performs), rebuild the harness, run it (`test-z3 fpa`) and require
  it to pass, then run the project's entire remaining unit suite
  (`test-z3 -a`) and require it to pass;
- run `/app/src/build/z3` on **hidden SMT cases** — other half-precision
  `fp.rem` operand pairs (different bit patterns, signs and expected
  encodings from every case above) that reach the same broken path — each
  must print exactly `unsat` and exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.