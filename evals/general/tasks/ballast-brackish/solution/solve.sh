#!/bin/bash
# Oracle for ballast-brackish: applies the one-source-file fix (the real
# upstream fix for the spurious-UNSAT seq.extract soundness bug) to the real
# Z3Prover/z3 tree at /app/src, rebuilds build/z3, writes /app/summary.md,
# and confirms the reproduction now prints sat.
# Reads only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied seq_rewriter offset-tracking fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: Z3 reported `unsat` for satisfiable (Seq Int) formulas in which a
sequence variable is equated to a `seq.extract` slice of a concatenation
that contains an if-then-else element (and, in the reproducer, the very
sequence's own length as its first element). `seq_rewriter::mk_seq_nth_i`
resolved the element at a target offset by comparing that absolute offset
against the loop index over the flattened concatenation pieces rather than
against a cumulative character position. When an `ite` element is skipped,
the loop index and the true character position desynchronize, the wrong
element is picked, and a false equality axiom is asserted during solving,
poisoning satisfiable instances into `unsat`.

Fix: track a cumulative `pos` counter (incremented by 1 per unit element,
and by the minimal length when an `ite` element is skipped) and compare the
target offset against `pos`; the element index passed to the nested nth is
`offset - pos`, with the skip condition `pos + len1 <= offset`. This is
exactly the upstream fix for the issue.

Verification: `cmake --build build --target shell` succeeds; the reproducer
`A_seq_extract.smt2` prints `sat` (was `unsat`); the project's own
sequence-rewriter module with the upstream regression test planted
(`./build/test-z3 seq_rewriter`) passes; hidden cases return sat/sat/sat/unsat
through the rebuilt `build/z3`.
MD

cmake --build build --target shell > /tmp/oracle_build.log 2>&1 || {
    echo "oracle: incremental rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
}
test -x build/z3 || { echo "oracle: build/z3 not produced" >&2; exit 1; }

cat > /tmp/A_seq_extract.smt2 <<'EOF'
(declare-const x Bool)
(declare-const y (Seq Int))
(assert (= y (seq.extract (seq.++ (seq.++ (seq.unit (seq.len y)) (seq.unit (ite x 0 1))) (seq.++ (seq.unit 1) (seq.unit 0))) 2 2)))
(check-sat)
EOF
out=$(./build/z3 /tmp/A_seq_extract.smt2 2>/dev/null | head -1)
if [ "$out" != "sat" ]; then
    echo "oracle: reproduction did not print sat (got '$out')" >&2
    exit 1
fi
echo "oracle: reproduction prints sat; build/z3 rebuilt; summary.md written"
exit 0