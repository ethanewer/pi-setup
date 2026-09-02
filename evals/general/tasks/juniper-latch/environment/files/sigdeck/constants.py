"""Golden tuning constants for the sigdeck release line.

These are frozen by release engineering -- the floor plan for release 3.1.0
pins them, and downstream tooling checksums this file. Do not change them
when tuning the deck; the analysis layer adapts to them instead.
"""

# Trailing-window length, in samples.
WINDOW = 6

# Quantization ladder (ascending). An RMS value is mapped to the largest
# rung r such that r <= value; ties (value exactly equal to a rung) map to
# that rung.
LADDER = [0.0, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
