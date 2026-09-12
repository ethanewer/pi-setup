#!/bin/bash
# Oracle for conduit-anchor: applies the fix to the real pytest-dev/pytest
# tree at /app/src (the timedelta relative-tolerance bug in the approx
# machinery), writes /app/summary.md, and proves the work with the project's
# own test tooling - the upstream regression tests (baked at /opt/golden),
# the whole testing/python/ suite, and the in-container reproduction script.
# Reads only /app, /solution and /opt/golden; never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# Sanity: must start from the pristine pinned parent tree.
test "$(git rev-parse HEAD)" = "fbab7c5dfe63a22f545207e8dc163ed61ad51d98" || {
    echo "oracle: /app/src is not at the pinned parent commit" >&2
    exit 1
}

# 1) Apply the fix to the single source file the bug lives in.
python3 /solution/apply_fix.py src/_pytest/python_api.py || {
    echo "oracle: apply_fix.py failed" >&2
    exit 1
}
test -z "$(git diff --name-only -- src/_pytest/python_api.py)" && {
    echo "oracle: fix did not change python_api.py" >&2
    exit 1
}

# 2) Reproduce-and-resolve proof: the in-container symptom script exits 0.
python3 /app/repro_symptom.py > /tmp/oracle_repro.log 2>&1 || {
    echo "oracle: repro_symptom.py did not pass; tail:" >&2
    tail -20 /tmp/oracle_repro.log >&2
    exit 1
}
grep -q "symptom resolved" /tmp/oracle_repro.log || {
    echo "oracle: repro script did not reach its success line" >&2
    exit 1
}

# 3) Validation-parity spot checks inside the fixed interpreter.
python3 - <<'PY'
from datetime import timedelta

import pytest

# negative / NaN relative tolerances and negative timedelta abs must be
# rejected with the plain-number messages
for bad, message in [
    (dict(rel=-0.25), "relative tolerance can't be negative"),
    (dict(rel=float("nan")), "relative tolerance can't be NaN"),
    (dict(abs=timedelta(seconds=-1)), "absolute tolerance can't be negative"),
]:
    try:
        pytest.approx(timedelta(seconds=1), **bad)
    except ValueError as exc:
        assert message in str(exc), (bad, exc)
    else:
        raise AssertionError(f"not rejected: {bad}")

# a timedelta is no longer a valid relative tolerance
try:
    pytest.approx(timedelta(seconds=1), rel=timedelta(seconds=1))
except TypeError as exc:
    assert "must be a number" in str(exc), exc
else:
    raise AssertionError("timedelta rel still accepted")

print("oracle validation checks ok")
PY

# 4) Prove the project's OWN suite: overlay the upstream regression test file
#    for this bug (baked at /opt/golden) and run the approx tests plus the
#    whole testing/python/ suite, then restore the tree.
cp /opt/golden/approx.py testing/python/approx.py
if ! python3 -m pytest testing/python/ -q -p no:cacheprovider > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: testing/python/ suite failed; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
grep -q "passed" /tmp/oracle_suite.log || {
    echo "oracle: suite log shows no passing run" >&2
    tail -5 /tmp/oracle_suite.log >&2
    exit 1
}
git checkout -q -- testing/python/approx.py

# 5) The graded tree: exactly one tracked file differs from the pinned tree.
STATUS=$(git status --porcelain)
case "$STATUS" in
    " M src/_pytest/python_api.py") : ;;
    *)
        echo "oracle: unexpected working-tree state:" >&2
        git status --porcelain >&2
        exit 1
        ;;
esac

# 6) Deliverable: the change summary.
cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: `pytest.approx()` rejected a plain number as the relative tolerance
(`rel=`) for `datetime`/`timedelta` comparisons, raising
`TypeError: relative tolerance for timedelta must be a timedelta, got float`
even though the same plain number works for every other value type, so
percentage-style relative tolerances could not be used for timedelta
comparisons at all. The same failure hit timedelta/datetime scalars inside
sequences and mappings.

Root cause: `ApproxTimedelta.__init__` demanded that `rel` be a `timedelta`
and never validated it; the scalar-routing helper used by sequences and
mappings always built an `ApproxScalar` for timedeltas.

Fix (in `src/_pytest/python_api.py`):

- `_approx_scalar` now routes `datetime`/`timedelta` scalars to
  `ApproxTimedelta`, so sequence/mapping comparisons use the timedelta
  comparison class.
- `ApproxTimedelta` accepts `rel` as a plain `int`/`float` and computes the
  effective tolerance as `rel * abs(expected)` (a `timedelta`); when both
  `abs` and `rel` are given the effective tolerance is the max of the two.
- Validation now mirrors the plain-number classes: a negative `rel`, a NaN
  `rel`, and a negative `timedelta` `abs` raise `ValueError` with the same
  messages; a `timedelta` passed as `rel` raises `TypeError` ("must be a
  number").

Verification: the upstream regression tests for this bug (the
`testing/python/approx.py` that landed with the fix, from /opt/golden) pass
when overlaid - including the relative-tolerance, validation, sequence and
mapping cases - the project's whole `testing/python/` suite stays green, the
in-container reproduction script (`/app/repro_symptom.py`) exits 0, and the
graded tree differs from the pinned parent commit in exactly the one source
file.
MD

echo "oracle: fix applied, summary written, upstream suite green"
exit 0