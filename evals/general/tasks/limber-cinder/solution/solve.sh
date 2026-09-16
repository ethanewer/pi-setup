#!/bin/bash
# Oracle for limber-cinder: applies the two-line upstream fix to the real
# pallets/jinja tree at /app/src (drop the membership alias from the
# default Undefined's fail-op line so membership falls back to the empty
# iteration and yields False; alias StrictUndefined.__contains__ to the
# fail-op so strict membership keeps raising), then writes the two declared
# deliverables /app/repro.py and /app/summary.md and proves the work in
# both directions: the reproduction must pass on the repaired tree and must
# fail against the pristine pre-fix copy baked at /opt/pre-fix-jinja when
# run under PYTHONPATH. Reads only /app, /solution and /opt.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the membership-on-undefined fix"

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction: `x in <undefined>` must evaluate to False, not abort.

Contract: renders a membership test against a name that is not defined,
using the DEFAULT undefined behaviour, prints whatever the render produced,
and exits 0 if and only if the render succeeded and produced exactly the
string "False". On the unfixed library the render raises UndefinedError and
this script exits non-zero, reproducing the reported symptom.
"""
from jinja2 import Environment

rendered = Environment().from_string('{{ "foo" in missing }}').render()
print(rendered)
if rendered != "False":
    raise SystemExit("expected rendered output 'False', got %r" % (rendered,))
PY
chmod +x /app/repro.py

cat > /app/summary.md <<'MD'
# limber-cinder fix summary

## Symptom
Templates that test membership with `in` / `not in` against a name that is
not defined aborted rendering with `jinja2.exceptions.UndefinedError`
(`'missing' is undefined`) instead of evaluating the membership test to
false, which is what the previous major version did and what the
documentation promises.

## Root cause
During the 3.0 development cycle the default `Undefined` type's generic
fail-operation alias line started including `__contains__`. That wired the
`in` operator to `_fail_with_undefined_error`, so any membership test
against an undefined value raised instead of falling back to the base
object's membership behaviour (empty iteration, so the test is false).

## Change
In the runtime source: removed `__contains__` from the default
`Undefined` fail-op alias line (`__call__ = __getitem__ =
_fail_with_undefined_error`), so `'foo' in missing` now evaluates False
(and `not in` True, in conditions too). Added
`__contains__ = Undefined._fail_with_undefined_error` to
`StrictUndefined`, so users who opted into strict-undefined mode still get
a raise for membership on undefined values.

## Verification
- `/app/repro.py` fails on the unmodified tree (the render raises) and
  passes on the repaired tree.
- The project's own regression test for this bug (`test_default_undefined`
  and `test_strict_undefined` from the fix-era test suite) passes.
- The previously-existing test files pass unchanged.
MD

# Prove the work in both directions.
if ! python3 /app/repro.py > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: repro failed on the repaired tree; tail:" >&2
    tail -10 /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
grep -q "False" /tmp/oracle_repro_fixed.out || {
    echo "oracle: repro did not print False on the repaired tree" >&2
    exit 1
}
PYTHONPATH=/opt/pre-fix-jinja python3 /app/repro.py > /tmp/oracle_repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "oracle: repro unexpectedly PASSED against the pristine pre-fix copy" >&2
    head -10 /tmp/oracle_repro_prefix.out >&2
    exit 1
fi
grep -q "UndefinedError" /tmp/oracle_repro_prefix.out || {
    echo "oracle: pre-fix failure was not the UndefinedError symptom" >&2
    head -10 /tmp/oracle_repro_prefix.out >&2
    exit 1
}
echo "oracle: repro FAILS on the pre-fix copy and PASSES on the repaired tree"

# The project's own regression test (pinned golden bytes) against the
# repaired tree.
if ! python3 -m pytest /opt/golden/test_api.py::TestUndefined::test_default_undefined \
     /opt/golden/test_api.py::TestUndefined::test_strict_undefined \
     -q -p no:cacheprovider > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: golden regression tests failed; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "2 passed" /tmp/oracle_golden.log || {
    echo "oracle: golden tests did not report 2 passed" >&2
    tail -5 /tmp/oracle_golden.log >&2
    exit 1
}
echo "oracle: the project's own regression tests pass on the repaired tree"
echo "oracle: DONE"
exit 0