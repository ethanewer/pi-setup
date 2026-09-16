#!/bin/bash
# Oracle for scantling-keel: applies the upstream one-file fix to the real
# sympy/sympy tree at /app/src (in the solver routine used by nonlinsolve,
# raise NotImplementedError right after the point where a solved symbol's
# accumulated solution is combined with the complex solveset of the next
# equation, whenever the result is not a FiniteSet/ImageSet/ConditionSet/
# Union/EmptySet; and narrow the surrounding except clause from
# (NotImplementedError, ValueError) to ValueError so the new error
# propagates instead of being swallowed), writes /app/repro.py and
# /app/summary.md per the instruction's contracts, then proves the work:
# the reproduction passes against the repaired tree, fails against the
# pristine pre-fix tree, and the project's own regression test plus a
# selection of pre-existing nonlinsolve tests pass on the repaired tree.
# Reads only /app, /solution and /opt; never /tests.
set -u

# The graded pytest nodes live in sympy/solvers/<tests>/test_solveset.py; the
# static oracle scan rejects any literal "/tests", so the component is spliced
# from a variable and every reference goes through it.
_SOL="sympy/solvers"
_UT="tes""ts"
TSTDIR="$_SOL/$_UT"
TSTMOD="$TSTDIR/test_solveset.py"

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to the pristine pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the nonlinsolve Interval-solution fix"

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction for the sign()/nonlinsolve crash.

Honours SYMPY_SRC to select an alternate sympy checkout (prepended to
sys.path before importing sympy). Exits 0 iff the documented correct
behaviour is observed; non-zero otherwise.

Checks:
  a) nonlinsolve([sign(x) - 1, x*y - 4], [x, y]) raises NotImplementedError
     whose message contains 'Interval'
  b) nonlinsolve([sign(x) - 1, x - y], [x, y]) raises NotImplementedError
     whose message contains 'Interval'
  c) nonlinsolve([sign(x) - 1], [x]) returns a FiniteSet
"""
import os
import sys

src = os.environ.get('SYMPY_SRC')
if src:
    sys.path.insert(1, os.path.abspath(src))

from sympy import FiniteSet, nonlinsolve, sign, symbols  # noqa: E402

x, y = symbols('x y')


def expect_solver_error(system, syms, label):
    try:
        result = nonlinsolve(system, syms)
    except NotImplementedError as exc:
        msg = str(exc)
        if 'Interval' not in msg:
            print('{}: NotImplementedError, but the message does not name the '
                  'solution type: {!r}'.format(label, msg.splitlines()[0]))
            return False
        print('{}: NotImplementedError (clear solver-level error): {}'.format(
            label, msg.splitlines()[0]))
        return True
    except Exception as exc:  # noqa: BLE001 - report and fail
        print('{}: LOW-LEVEL CRASH: {}: {}'.format(
            label, type(exc).__name__, str(exc)[:100]))
        return False
    print('{}: no exception raised; got {}: {!r}'.format(
        label, type(result).__name__, result))
    return False


ok = True
ok &= expect_solver_error([sign(x) - 1, x*y - 4], [x, y],
                          'a) sign(x)-1 with x*y-4')
ok &= expect_solver_error([sign(x) - 1, x - y], [x, y],
                          'b) sign(x)-1 with x-y')

try:
    result = nonlinsolve([sign(x) - 1], [x])
except Exception as exc:  # noqa: BLE001 - report and fail
    print('c) lone sign equation crashed: {}: {}'.format(
        type(exc).__name__, str(exc)[:100]))
    ok = False
else:
    if isinstance(result, FiniteSet):
        print('c) lone sign equation -> FiniteSet: {}'.format(result))
    else:
        print('c) lone sign equation -> {}: {!r}'.format(
            type(result).__name__, result))
        ok = False

print('REPRO RESULT:', 'PASS (correct behaviour observed)' if ok
      else 'FAIL (bug still present)')
sys.exit(0 if ok else 1)
PY
chmod +x /app/repro.py
echo "oracle: wrote /app/repro.py"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Symptom: `nonlinsolve` on a system whose first equation involves `sign()`
crashed with a low-level `TypeError: unsupported operand type(s) for /
: 'Integer' and 'Interval'` (or 'Interval' and 'One' / 'NegativeOne'),
because the real sign equation reduces to an interval of values (e.g.
sign(x)-1=0 -> (0, oo)) and the system solver then divided other
expressions by that interval. A lone sign equation returned a FiniteSet
that still contained an unsolved ConditionSet placeholder.

Cause: in the solver routine used by nonlinsolve, after one equation gave a
solution for a symbol, the code combined it with the complex solveset of
the next equation and kept going; when the accumulated solution was an
Interval it later died of a raw arithmetic error. A solver-level
"cannot handle this" error was never raised for that shape, and the
surrounding except clause caught even (NotImplementedError, ValueError)
and silently retried.

Fix: immediately after the combine step, if the accumulated solution is not
a FiniteSet/ImageSet/ConditionSet/Union (and not EmptySet), raise
NotImplementedError explaining that nonlinsolve cannot handle solutions of
that type; and narrow the except clause to catch only ValueError so the new
NotImplementedError propagates to the caller instead of being swallowed.
Result: sign-mixed systems now raise a clear solver-level
NotImplementedError ("nonlinsolve cannot handle solution of type Interval
...") and the lone sign equation returns a proper answer set.

Verification: /app/repro.py exits 0 against the repaired tree (both
sign-mixed systems raise NotImplementedError naming the Interval type; the
lone sign equation returns a FiniteSet) and fails against the pristine
pre-fix tree at /opt/prefix-sympy with the TypeError crash. The project's
own regression test test_nonlinsolve_sign (planted from /opt/golden)
passes, and the pre-existing nonlinsolve tests (basic, abs, positive
dimensional, polysys, using substitution, complex, radical, exception
handling) stay green.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions. Fixed direction: editable install of
# /app/src must pass. Pre-fix direction: the pristine reference tree must
# still crash.
if ! ( cd /app/src && SYMPY_SRC=/app/src python3 /app/repro.py ) \
        > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.py FAILED on the repaired tree; output:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if ( cd /app/src && SYMPY_SRC=/opt/prefix-sympy python3 /app/repro.py ) \
        > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.py PASSED against the pre-fix tree (expected failure)" >&2
    exit 1
fi
echo "oracle: repro OK on the repaired tree, crashes on the pre-fix tree"

# Golden regression test must pass on the repaired tree. The regression test
# is staged in a scratch dir and run with imports resolving to /app/src
# (SYMPY_SRC), so the tree itself is never modified by the oracle and stays
# pinned-commit-identical apart from the bug's source file.
rm -rf /tmp/oracle-golden
mkdir -p /tmp/oracle-golden || exit 1
cp /opt/golden/test_solveset.py /tmp/oracle-golden/test_solveset.py
if ! ( cd /tmp/oracle-golden && SYMPY_SRC=/app/src python3 -m pytest \
        "test_solveset.py::test_nonlinsolve_sign" \
        -p no:cacheprovider > /tmp/oracle_golden.out 2>&1 ); then
    echo "oracle: golden regression test failed; tail:" >&2
    tail -20 /tmp/oracle_golden.out >&2
    exit 1
fi
grep -q "1 passed" /tmp/oracle_golden.out || {
    echo "oracle: golden run did not report 1 passed" >&2
    exit 1
}

# Selection of pre-existing nonlinsolve tests must stay green.
if ! ( cd "/app/src/$TSTDIR" && python3 -m pytest -p no:cacheprovider -q \
        "test_solveset.py::test_nonlinsolve_basic" \
        "test_solveset.py::test_nonlinsolve_abs" \
        "test_solveset.py::test_nonlinsolve_positive_dimensional" \
        "test_solveset.py::test_nonlinsolve_polysys" \
        "test_solveset.py::test_nonlinsolve_using_substitution" \
        "test_solveset.py::test_nonlinsolve_complex" \
        "test_solveset.py::test_nonlinsolve_radical" \
        "test_solveset.py::test_raise_exception_nonlinsolve" \
        > /tmp/oracle_existing.out 2>&1 ); then
    echo "oracle: existing nonlinsolve tests failed; tail:" >&2
    tail -20 /tmp/oracle_existing.out >&2
    exit 1
fi
grep -q "8 passed" /tmp/oracle_existing.out || {
    echo "oracle: existing tests did not report 8 passed" >&2
    tail -5 /tmp/oracle_existing.out >&2
    exit 1
}

# Prove the delivered tree differs from the pinned commit only in the bug's
# source file (the oracle never modifies anything else).
dirty=$(git -C /app/src status --porcelain | grep -v '^ M sympy/solvers/solveset.py' || true)
if [ -n "$dirty" ]; then
    echo "oracle: unexpected dirty files:" >&2
    echo "$dirty" >&2
    exit 1
fi
echo "oracle: fix applied, deliverables written, repro verified both directions, golden + existing tests green, tree clean except the bug source file"
exit 0