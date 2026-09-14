#!/bin/bash
# /app/repro.sh -- authored reproduction for the tiny-slope axline bug.
#
# Contract (see instruction.md): takes no arguments, runs entirely offline,
# drives the project's own test runner (`python3 -m pytest`) with a scenario
# test file authored for this bug, prints the test run output, removes the
# scenario file, and exits with the test run's exit status. Exits non-zero on
# a checkout that still has the bug (a 1e-14-slope axline renders exactly
# horizontal: the line's transform maps the two data points to the same y,
# dy == 0.0) and zero on a fixed checkout (dy is small but non-zero).
set -u

SRC=/app/src
TESTFILE=test_zz_axline_tilt_repro.py
LOG=/tmp/repro-axline.log

cd "$SRC/lib/matplotlib" || exit 1
cd tests || exit 1

trap 'rm -f "$TESTFILE"' EXIT

cat > "$TESTFILE" <<'EOF'
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def test_zz_axline_tilt_repro():
    fig, ax = plt.subplots()
    line = ax.axline((0, 0), slope=1e-14)
    p1 = line.get_transform().transform_point((0, 0))
    p2 = line.get_transform().transform_point((1, 1))
    dy = p2[1] - p1[1]
    # a small non-zero slope must keep a slight tilt...
    assert 0 < dy < 4e-12, f"dy={dy!r}"
    # ...while an exactly-zero slope stays horizontal
    line0 = ax.axline((0, 0), slope=0)
    q1 = line0.get_transform().transform_point((0, 1))
    q2 = line0.get_transform().transform_point((1, 1))
    assert (q2[1] - q1[1]) == 0.0
EOF

PYTHONDONTWRITEBYTECODE=1 python3 -m pytest "$TESTFILE" -p no:cacheprovider 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"