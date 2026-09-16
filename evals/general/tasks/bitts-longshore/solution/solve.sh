#!/bin/bash
# Oracle for bitts-longshore: applies the upstream fix to the real
# sympy/sympy tree at /app/src (in Mod.number_eval, the list of non-mod
# factors of p must be rebuilt from the already-filtered non_mod_l rather
# than from all of p.args, so a Mod factor is no longer duplicated into both
# the mod and the non-mod lists and the inner residue is no longer squared),
# installs the two deliverables /app/repro.sh (copied from
# /solution/repro.sh) and /app/summary.md, and proves the work: the
# reproduction must fail against a scratch copy of the tree with the pre-fix
# code restored and must pass against the fixed tree.
# Reads only /app, /solution and /tmp.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to the pristine pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the one-line fix in sympy/core/mod.py"

# ---- deliverable: the agent-facing reproduction contract -------------------
cp /solution/repro.sh /app/repro.sh
chmod +x /app/repro.sh
echo "oracle: installed /app/repro.sh"

# ---- deliverable: the change summary ---------------------------------------
cat > /app/summary.md <<'MD'
## Symptom

A modulo expression changes value when a symbol is declared integer. For
example, `Mod(2*Mod(x, 3), 5)` with `x` an ordinary symbol differs from the
same expression with `x` declared `integer=True` (after substituting the
integer symbol back): the inner remainder is multiplied by itself, i.e.
squared (`Mod(2*(Mod(x, 3))**2, 5)`), even though the integer assumption
must only add simplifications, never change the value. The same discrepancy
appears in the floor family `8*Mod(floor(x/64), 4)`.

## Root cause

In `Mod.number_eval`, when the modulus is an integer and every factor of the
dividend `p` reports being integer (which requires an integer-assumed
symbol), the list of non-mod factors was being rebuilt by iterating over
**all** of `p.args`. Factors of `p` that are themselves `Mod` expressions
were therefore added to the non-mod list *as well as* being kept in the mod
list: both copies survived, so the inner `Mod` appeared twice — squared.

## Change

In `sympy/core/mod.py`, the rebuild iterates over the already-filtered
`non_mod_l` instead of `p.args`, so a factor that is a `Mod` expression is
no longer duplicated. The fix is the smallest possible change: one line.

## Tests run

- My own reproduction `/app/repro.sh` (both reported families): fails on a
  pre-fix copy of the tree, passes after the fix.
- The project's arithmetic test module that covers Mod (test_arit in the
  core package): all tests pass.
- The upstream regression test for this bug (test_Mod with the new asserts):
  passes.
MD

# ---- prove the work: pre-fix copy must fail, fixed tree must pass -----------
if ! bash /app/repro.sh /app/src > /tmp/oracle_fixed.out 2>&1; then
    echo "oracle: repro failed on the repaired tree; output:" >&2
    tail -20 /tmp/oracle_fixed.out >&2
    exit 1
fi
echo "oracle: repro exits 0 on the repaired tree"
rm -rf /tmp/oracle_prefix
cp -a /app/src /tmp/oracle_prefix
git -C /tmp/oracle_prefix show HEAD:sympy/core/mod.py \
    > /tmp/oracle_prefix/sympy/core/mod.py
want=$(git -C /tmp/oracle_prefix rev-parse HEAD:sympy/core/mod.py)
have=$(git -C /tmp/oracle_prefix hash-object /tmp/oracle_prefix/sympy/core/mod.py)
[ "$have" = "$want" ] || { echo "oracle: pre-fix restore failed (hash $have != $want)" >&2; exit 1; }
if bash /app/repro.sh /tmp/oracle_prefix > /tmp/oracle_prefix.out 2>&1; then
    echo "oracle: repro PASSED on the pre-fix copy (expected failure); output:" >&2
    tail -20 /tmp/oracle_prefix.out >&2
    exit 1
fi
echo "oracle: repro exits nonzero on the pre-fix copy"
rm -rf /tmp/oracle_prefix
echo "oracle: deliverables written and both directions verified"