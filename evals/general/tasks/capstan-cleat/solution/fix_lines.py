#!/usr/bin/env python3
"""Oracle helper: apply the minimal upstream fix for the tiny-slope axline bug.

AxLine.get_transform decides the line is horizontal with
`np.isclose(slope, 0)`; numpy's default atol of 1e-8 treats any slope with
|slope| <= 1e-8 as zero and snaps the line perfectly horizontal. The upstream
fix compares `slope == 0` exactly, so only a true zero slope is horizontal
and tiny non-zero slopes keep their tilt.

Usage: fix_lines.py /path/to/lib/matplotlib/lines.py
"""
import sys

p = sys.argv[1]
s = open(p, encoding="utf-8").read()
buggy = "if np.isclose(slope, 0):"
if buggy not in s:
    sys.exit(f"FAIL: bug pattern {buggy!r} not found in {p}")
s = s.replace(buggy, "if slope == 0:")
open(p, "w", encoding="utf-8").write(s)
print("applied upstream fix: AxLine now treats only an exactly-zero slope as horizontal")