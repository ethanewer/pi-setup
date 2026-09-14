#!/bin/bash
# Oracle for capstan-cleat: applies the minimal upstream fix for the
# tiny-slope axline bug to the checkout at /app/src (AxLine.get_transform
# must treat only an exactly-zero slope as horizontal), writes the
# /app/repro.sh deliverable from the authored reproduction template, and
# proves the repaired direction with the project's own test runner: the
# authored reproduction, the upstream golden regression test
# (test_axline_small_slope, extracted at build time into /opt/golden), and a
# subset of the project's own existing axline/line tests.
set -e

SRC=/app/src

# 1. the source fix (the exact upstream change)
python3 /solution/fix_lines.py "$SRC/lib/matplotlib/lines.py"

# 2. the authored reproduction deliverable
cp /solution/repro-template.sh /app/repro.sh
chmod +x /app/repro.sh

# 3. prove the repaired direction with the project's own runner
echo "== repaired tree: authored repro must pass =="
bash /app/repro.sh

echo "== golden regression test (fix-commit test_lines.py, run from /tmp) =="
cp /opt/golden/test_lines.py /tmp/test_lines_golden.py
cd "$SRC"
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest \
  "/tmp/test_lines_golden.py::test_axline_small_slope" \
  -p no:cacheprovider -q

echo "== the project's own existing axline/line tests (parent nodes) =="
cd "$SRC"/lib/matplotlib
cd tests
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest \
  "test_axes.py::test_axline_args" \
  "test_lines.py::test_axline_setters" \
  "test_lines.py::test_segment_hits" \
  "test_lines.py::test_invalid_line_data" \
  "test_lines.py::test_linestyle_variants" \
  -p no:cacheprovider -q

echo "== deliverable: root-cause note =="
python3 - <<'EOF'
note = """Root cause

Axes.axline renders an infinite reference line by computing, at draw time,
the transform that maps data coordinates onto the line. When the line is
given as a point and a slope, AxLine.get_transform () decides whether the
line is horizontal with np.isclose(slope, 0). numpy's np.isclose uses a
default absolute tolerance of 1e-8, so every slope with |slope| <= 1e-8 is
treated as zero, and the geometry code then draws the line perfectly
horizontal through the anchor point. A user asking for slope=1e-14 (or any
value up to about 1e-8) gets a flat line instead of the requested slight
tilt; the renderer also intersects the wrong data.

Minimal change

lib/matplotlib/lines.py, one line: the horizontal test was changed from
    if np.isclose(slope, 0):
to
    if slope == 0:
so only a slope that is exactly zero (0.0 / -0.0) takes the horizontal
branch. Every non-zero slope, however small, now keeps its true tilt through
the general intersection code path.
"""
open('/app/explanation.md', 'w', encoding='utf-8').write(note)
print('wrote /app/explanation.md')
EOF

echo "== oracle: all steps passed =="