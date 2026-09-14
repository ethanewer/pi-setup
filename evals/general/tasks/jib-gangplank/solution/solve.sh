#!/usr/bin/env bash
# Oracle for jib-gangplank: applies the minimal upstream fix to the
# matplotlib checkout at /app/src (guard in Axes.pie that raises
# ValueError('All wedge sizes are zero') when the wedge sizes sum to zero),
# writes the required reproduction script /app/reproduce.py, then proves the
# fix with the reproduction and with the project's own tests.
set -e

python3 /solution/fix_pie.py /app/src/lib/matplotlib/axes/_axes.py

cat > /app/reproduce.py <<'PYEOF'
#!/usr/bin/env python3
"""Reproduction for the all-zero pie wedges bug.

Contract: exits 0 and prints REPRO-OK exactly when the pie chart function
raises ValueError with a message containing 'All wedge sizes are zero' for
an input in which every wedge size is zero; any other outcome prints what
actually happened and exits nonzero.
"""
import sys
import traceback

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

try:
    fig, ax = plt.subplots()
    ax.pie([0, 0], labels=['A', 'B'])
except ValueError as e:
    if 'All wedge sizes are zero' in str(e):
        print('REPRO-OK')
        sys.exit(0)
    print('pie call raised ValueError with an unexpected message: %r' % str(e))
    traceback.print_exc()
    sys.exit(1)
except Exception as e:
    print('pie call raised an unexpected %s: %r' % (type(e).__name__, str(e)))
    traceback.print_exc()
    sys.exit(1)
else:
    print('pie call did not raise: no error of any kind was produced')
    sys.exit(1)
PYEOF
chmod +x /app/reproduce.py

echo "== reproduction against the repaired tree =="
cd /app/src && python3 /app/reproduce.py

echo "== golden regression test (fix-commit test_axes.py, run from a /tmp copy so the tree stays clean) =="
cp /opt/golden/test_axes.py /tmp/jg_golden_test_axes.py
cd /app/src && python3 -m pytest \
  "/tmp/jg_golden_test_axes.py::test_pie_all_zeros" \
  -p no:cacheprovider -q

echo "== the project's own existing pie tests (no image comparison) =="
cd /app/src/lib/matplotlib && cd tests && python3 -m pytest \
  "test_axes.py::test_pie_textprops" \
  "test_axes.py::test_pie_get_negative_values" \
  "test_axes.py::test_pie_invalid_explode" \
  "test_axes.py::test_pie_invalid_labels" \
  "test_axes.py::test_pie_invalid_radius" \
  "test_axes.py::test_normalize_kwarg_pie" \
  "test_axes.py::test_pie_hatch_single" \
  "test_axes.py::test_pie_hatch_multi" \
  "test_axes.py::test_pie_non_finite_values" \
  -p no:cacheprovider -q

echo "== oracle: all steps passed =="