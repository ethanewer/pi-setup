#!/bin/bash
# Oracle for corvette-towpath: writes the reproduction deliverable, applies
# the minimal authored fix to the real Z3Prover/z3 tree at /app/src (the
# one-line sticky_h1 -> sticky_h2 swap in the h2 rounding step of
# fpa2bv_converter::mk_fma(), matching the upstream fix), writes
# /app/summary.md, then proves the work with the project's own machinery:
# rebuild the solver and the unit-test harness incrementally and offline, and
# confirm the reproduction now prints `unsat` and the project's own
# smt_context unit module still passes. Reads only /app and /solution; never
# /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# Deliverable 1: the reproduction script. It honours $Z3_BIN (default
# /app/src/build/z3), writes its query to a temporary file, and prints
# exactly one line - the solver verdict (`sat` on the unpatched tree, `unsat`
# once the tree is fixed).
cat > /app/reproduce.sh <<'REPRO'
#!/bin/bash
# Reproduction for the Z3 fp.fma binary16 (5,11) mis-rounding defect.
# Contract: prints exactly one line: the solver's verdict, `sat` or `unsat`.
set -u
Z3="${Z3_BIN:-/app/src/build/z3}"
tmp=$(mktemp /tmp/repro.XXXXXX.smt2) || exit 2
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(declare-const xb (_ BitVec 16))
(declare-const yb (_ BitVec 16))
(assert (= x ((_ to_fp 5 11) xb)))
(assert (= y ((_ to_fp 5 11) yb)))
(assert (= xb #b1000001111000111))
(assert (= yb #b0011110111000000))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.fma RNE x y x)) #x889b)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
"$Z3" "$tmp"
REPRO
chmod +x /app/reproduce.sh

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied one-line fp.fma sticky-bit fix (mk_fma h2 path)"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: Z3 computed an IEEE 754 fused multiply-add encoding that is one unit in
the last place (ulp) away from the correctly rounded value for some binary16
(`(_ FloatingPoint 5 11)`) operand triples. With both operands pinned to
concrete bit patterns the query
`(assert (not (= ((_ fp.to_ieee_bv 16) (fp.fma RNE x y x)) #x889b)))`
answered `sat` where the operands fully determine the operation and the
answer must be `unsat`; the bit-vector encoding the fpa2bv pipeline computed
for the fused result differed from the true IEEE 754 encoding in its low bit.

Root cause: in the fpa2bv conversion of `fp.fma`
(`fpa2bv_converter::mk_fma` in `src/ast/fpa/fpa2bv_converter.cpp`), the
second rounding step (h2) builds its sticky-bit reduction from the FIRST
step's discarded-bit range (`sticky_h1`) instead of from its own low bits
(`sticky_h2`). The lowered operation therefore drops the true h2 sticky bits
and some inexact results round exactly as if their late bits were zero, which
moves the computed encoding one ulp.

Fix: in the single line that computes `sticky_h2_red`, feed
`OP_BREDOR` with `sticky_h2` (the second step's own discarded-bit range)
instead of `sticky_h1`. The h1 path is untouched; no other code changes.

Verification: rebuilt the solver and the project's own unit-test harness
(`cmake --build build --target shell`, then `--target test-z3`); the
reproduction above prints `unsat`; the project's own `smt_context` unit
module passes.
MD

# Prove the tree builds and behaves correctly, all offline and incremental.
if ! cmake --build build --target shell -j1 > /tmp/oracle_shell.log 2>&1; then
    echo "oracle: shell rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_shell.log >&2
    exit 1
fi
if ! cmake --build build --target test-z3 -j1 > /tmp/oracle_tz.log 2>&1; then
    echo "oracle: test-z3 rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_tz.log >&2
    exit 1
fi
out=$(Z3_BIN=/app/src/build/z3 /app/reproduce.sh 2>/tmp/oracle_repro.err)
if [ "$out" != "unsat" ]; then
    echo "oracle: reproduction printed '$out', expected 'unsat'" >&2
    head -5 /tmp/oracle_repro.err >&2
    exit 1
fi
if ! ./build/test-z3 smt_context > /tmp/oracle_smoke.log 2>&1; then
    echo "oracle: smt_context unit module failed after the fix; tail:" >&2
    tail -20 /tmp/oracle_smoke.log >&2
    exit 1
fi
grep -q "PASS" /tmp/oracle_smoke.log || {
    echo "oracle: smt_context did not actually run and pass" >&2
    exit 1
}
echo "oracle: fix verified (repro unsat, smt_context module passes)"