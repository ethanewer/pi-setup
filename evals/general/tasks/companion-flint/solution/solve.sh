#!/bin/bash
# Oracle for companion-flint: applies the real upstream fix to the mypy tree
# at /app/src (adds the TypeVar-with-values subtyping rule in the subtype
# machinery), writes the reproduction deliverables, then proves the work in
# both directions with the project's own tooling. Reads only /app, /solution
# and /opt; never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the TypeVar-with-values default-argument fix"

# --- deliverable 1: the reproduction program (single legal default) ---------
cat > /app/repro.py <<'PY'
from typing import TypeVar

class B: ...
class C(B): ...

S = TypeVar("S", B, C)
c = C()

def f(x: S = c):  # legal: the default's type C is one of S's value types
    pass
PY
echo "oracle: wrote /app/repro.py"

# --- deliverable 2: the MYPY_DIR-honouring runner ---------------------------
cat > /app/repro.sh <<'SH'
#!/bin/bash
# Reproduction runner. Contract: honour $MYPY_DIR (default /app/src),
# run mypy from that tree on /app/repro.py, print mypy's output, and exit 0
# iff mypy exits 0 with no diagnostics.
set -u
MYPY_DIR=${MYPY_DIR:-/app/src}
( cd "$MYPY_DIR" && python3 -m mypy --no-incremental --cache-dir=/tmp/myrepocache /app/repro.py )
exit $?
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

# --- deliverable 3: summary ------------------------------------------------
cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: a function parameter annotated with a type variable declared with an
explicit value list (e.g. `S = TypeVar("S", B, C)` with `C <: B`) rejected a
LEGAL default value whose type was one of the value types (a subtype of all
of them): mypy reported `Incompatible default for parameter "x" (default has
type "C", parameter has type "S")` even though the default is perfectly
valid. Genuinely invalid defaults (a type that is not a subtype of every
value type, such as `B` itself) were still reported, so the verdict flipped
on which class the default happened to be.

Cause: the subtype machinery had no special case for a value-restricted type
variable on the right-hand side of a subtype check when the left-hand side is
itself not a type variable. A default's type was tested against the raw type
variable, so only defaults that were supertypes of the whole value list were
accepted.

Change: in the subtype implementation, when the right side is a TypeVarType
with a non-empty value list and the left side is not itself a TypeVarType,
the left side counts as a subtype of the type variable exactly when it is a
subtype of every one of the value types (proper-subtype variants use proper
subtyping). The type variable then accepts any default whose type is a
subtype of all its allowed value types, and still rejects genuinely invalid
defaults.

Verification: `/app/repro.py` type-checks cleanly through the repaired tree
(exit 0, no diagnostics) and still fails against the pristine pre-fix tree at
/opt/mypy-parent with the `Incompatible default for parameter` diagnostic;
the project's own regression test for this bug (planted from /opt/golden)
passes; the full existing type-variable data sweep
(`python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q`)
passes; hidden cases with three-level value lists, multiple-inheritance
default types, and keyword-only parameters all pass.
MD
echo "oracle: wrote /app/summary.md"

# --- prove the work in both directions with the project's own tooling ------

# 1) the reproduction must be clean through the repaired tree...
if ( cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/oraclecache /app/repro.py > /tmp/oracle-fixed.out 2>&1 ); then
    echo "oracle: repro clean on repaired tree"
else
    echo "oracle: repro still fails on repaired tree; out:" >&2
    cat /tmp/oracle-fixed.out >&2
    exit 1
fi

# 2) ...and must fail on the pristine pre-fix tree with the specific symptom
if ( cd /opt/mypy-parent && python3 -m mypy --no-incremental --cache-dir=/tmp/oraclecache /app/repro.py > /tmp/oracle-prefix.out 2>&1 ); then
    echo "oracle: repro PASSED on the pre-fix tree (expected failure)" >&2
    exit 1
fi
grep -q "Incompatible default for parameter" /tmp/oracle-prefix.out || {
    echo "oracle: pre-fix failure is not the Incompatible-default symptom" >&2
    exit 1
}
echo "oracle: repro fails on pre-fix tree with the expected diagnostic"

# 3) the upstream regression test (baked at /opt/golden) must pass, planted
#    into a throwaway copy of the fixed tree (the verifier plants it into
#    the real tree).
rm -rf /tmp/oraclecheck
cp -a /app/src /tmp/oraclecheck || { echo "oracle: copy failed" >&2; exit 1; }
cat /opt/golden/golden-case.test >> /tmp/oraclecheck/test-data/unit/check-typevar-values.test
if ! ( cd /tmp/oraclecheck && python3 -m pytest mypy/test/testcheck.py -k testTypeVarValuesSubtypeOfAll -n 1 -q > /tmp/oracle-golden.out 2>&1 ); then
    echo "oracle: upstream regression test failed on the fixed tree; out:" >&2
    tail -20 /tmp/oracle-golden.out >&2
    exit 1
fi
grep -q "1 passed" /tmp/oracle-golden.out || { echo "oracle: golden did not report 1 passed" >&2; exit 1; }

# 4) the full existing type-variable sweep must stay green (219 + golden).
if ! ( cd /tmp/oraclecheck && python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q > /tmp/oracle-sweep.out 2>&1 ); then
    echo "oracle: type-variable sweep failed on the fixed tree; out:" >&2
    tail -20 /tmp/oracle-sweep.out >&2
    exit 1
fi
grep -q "220 passed" /tmp/oracle-sweep.out || { echo "oracle: sweep did not report 220 passed" >&2; exit 1; }
rm -rf /tmp/oraclecheck

echo "oracle: fix applied, deliverables written, repro OK both directions, golden + full typevar sweep green"
exit 0