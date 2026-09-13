#!/usr/bin/env bash
# Oracle for ballast-longshore: applies the minimal upstream fix to the
# matplotlib checkout at /app/src (dispatch set_useOffset on type instead of
# value equality, so only real bools toggle offset mode and the number 1 is a
# numeric offset), then proves the fix with the issue reproduction and with
# the project's own tests.
set -e

python3 /solution/fix_ticker.py /app/src/lib/matplotlib/ticker.py

echo "== issue reproduction: set_useOffset(1) must be a numeric offset =="
cd /app/src && python3 - <<'EOF'
import matplotlib
matplotlib.use('Agg')
from matplotlib.ticker import ScalarFormatter
f = ScalarFormatter()
f.set_useOffset(1)
print('offset =', repr(f.offset), ' useOffset =', repr(f.get_useOffset()))
assert f.offset == 1 and f.get_useOffset() is False
print('ok')
EOF

echo "== golden regression tests (fix-commit test_ticker.py, run from /tmp so the tree stays clean) =="
cd /app/src && cp /opt/golden/test_ticker.py /tmp/test_ticker_golden.py
cd /app/src && python3 -m pytest \
  "/tmp/test_ticker_golden.py::TestScalarFormatter::test_set_use_offset_int" \
  "/tmp/test_ticker_golden.py::TestScalarFormatter::test_set_use_offset_bool" \
  -p no:cacheprovider -q

echo "== the project's own existing ticker tests (TestScalarFormatter) =="
cd /app/src/lib/matplotlib && cd tests && python3 -m pytest \
  "test_ticker.py::TestScalarFormatter::test_use_offset" \
  "test_ticker.py::TestScalarFormatter::test_set_use_offset_float" \
  "test_ticker.py::TestScalarFormatter::test_useMathText" \
  "test_ticker.py::TestScalarFormatter::test_offset_value" \
  "test_ticker.py::TestScalarFormatter::test_scilimits" \
  -p no:cacheprovider -q

echo "== deliverable: root-cause note =="
python3 - <<'EOF'
note = """Root cause

ScalarFormatter.set_useOffset dispatches between its two documented input
kinds (bool: toggle offset mode; number: force an explicit offset) with the
membership test `if val in [True, False]:`. Python's `in` uses value
equality, and since 1 == True (and 0 == False, and any numpy scalar equal to
either), the numeric value 1 is captured by the boolean branch: it resets the
offset to 0 and turns automatic offset mode on, instead of storing the
numeric offset 1 with automatic mode off.

Minimal change

`lib/matplotlib/ticker.py`, ScalarFormatter.set_useOffset: replace
`if val in [True, False]:` with `if isinstance(val, bool):` so only actual
boolean values (True/False) toggle the mode and every number - including 1 -
is treated as an explicit numeric offset.
"""
open('/app/explanation.md', 'w', encoding='utf-8').write(note)
print('wrote /app/explanation.md')
EOF

echo "== oracle: all steps passed =="