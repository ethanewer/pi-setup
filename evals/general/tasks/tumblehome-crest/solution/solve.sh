#!/bin/bash
# Oracle for tumblehome-crest. Applies the real fix for the negative-narrowing
# false positive to the mypy source tree at /app/src, writes the reproduction
# deliverable, and proves both stay green. This is the reference solution.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply /solution/checker-fix.patch || { echo "oracle: failed to apply fix patch" >&2; exit 1; }

cat > /app/repro.py <<'PY'
from enum import Enum
class Color(Enum):
    RED = 1
def count(colors: list[Color]) -> None:
    counts: dict[Color, int] = {}
    for color in colors:
        if color not in counts:
            counts[color] = 0
        counts[color] += 1
PY

if ! python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/oracle-cache /app/repro.py > /tmp/oracle-repro.log 2>&1; then
    echo "oracle: reproduction still fails after the fix" >&2
    tail -5 /tmp/oracle-repro.log >&2
    exit 1
fi
grep -q "Success: no issues found" /tmp/oracle-repro.log || {
    echo "oracle: repro did not report Success" >&2
    tail -5 /tmp/oracle-repro.log >&2
    exit 1
}

if ! python3 -m pytest mypy/test/testcheck.py -k 'Narrowing or Narrow' -q > /tmp/oracle-pytest.log 2>&1; then
    echo "oracle: narrowing suite subset failed after the fix" >&2
    tail -8 /tmp/oracle-pytest.log >&2
    exit 1
fi

echo "oracle: fix applied, reproduction green, narrowing suite subset green"
exit 0