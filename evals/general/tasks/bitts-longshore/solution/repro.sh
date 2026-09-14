#!/bin/bash
# /app/repro.sh [REPO_DIR]
# Failing reproduction for bitts-longshore: an integer-assumed symbol must
# not change the value of a modulo expression. Plants a temporary pytest
# test file into the target repository's own test directory, runs the
# project's own test runner on exactly that file, removes the file again,
# and exits 0 iff the symptom is absent (the temporary test passed).
set -u
REPO="${1:-/app/src}"
[ -d "$REPO" ] || { echo "repro: no such repository directory: $REPO" >&2; exit 2; }
TESTFILE="$REPO/sympy/core/tests/test_repro_mod_integer_stability.py"
rm -f "$TESTFILE"
trap 'rm -f "$TESTFILE"' EXIT
cat > "$TESTFILE" <<'PYEOF'
# Temporary reproduction: integer-assumed symbols must not change Mod values.
from sympy import Symbol, Mod, floor


def test_integer_assumption_does_not_change_mod():
    # nested-mod family: the inner residue must not end up squared
    x0 = Symbol('x0')
    x0i = Symbol('x0i', integer=True)
    assert Mod(2*Mod(x0, 3), 5) == Mod(2*Mod(x0i, 3), 5).xreplace({x0i: x0})
    # floor family: the same contract must hold there too
    x1 = Symbol('x1')
    x1i = Symbol('x1i', integer=True)
    assert 8*Mod(floor(x1/64), 4) == 8*Mod(floor(x1i/64), 4).xreplace({x1i: x1})
PYEOF
(
    cd "$REPO" || exit 2
    PYTHONPATH="$REPO" python -m pytest "$TESTFILE" -p no:cacheprovider
)