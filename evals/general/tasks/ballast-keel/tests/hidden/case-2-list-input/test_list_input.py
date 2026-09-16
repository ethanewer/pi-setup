#!/usr/bin/env python3
"""Hidden case 2 (ballast-keel): list-typed note inputs mixing deviated and
plain notes must be converted elementwise, preserving deviations by default.

The upstream regression test only calls note_to_hz with a single string and
a single '-30' deviation. These cases exercise the iterable-input branch of
the same code path (it returns an ndarray) with flats, sharps and mixed
deviated/plain notes in one call, and additionally assert that converting
the plain counterpart via note_to_hz in the same call yields a *different*
(detuned) frequency for the deviated entry.
"""
from __future__ import annotations

import numpy as np
import librosa


def expected(note_midi: float, cents: float) -> float:
    return 440.0 * 2.0 ** ((note_midi + cents / 100.0 - 69.0) / 12.0)


# (list input, list of (plain-note midi, cents) expectations in same order)
CASES = [
    (["C2-30", "C2"], [(36, -30), (36, 0)]),
    (["Bb2-25", "B2"], [(46, -25), (47, 0)]),
    (["F#3+17", "F#3", "G3-10"], [(54, +17), (54, 0), (55, -10)]),
    (["A4-50", "A4+50", "A4"], [(69, -50), (69, +50), (69, 0)]),
]

failures = []
for notes, exps in CASES:
    hz = librosa.note_to_hz(notes)
    hz = np.atleast_1d(hz)
    if hz.shape != (len(notes),):
        failures.append(f"{notes}: expected shape ({len(notes)},), got {hz.shape}")
        continue
    for i, (note, (midi, cents)) in enumerate(zip(notes, exps)):
        exp = expected(midi, cents)
        if not np.isclose(hz[i], exp, rtol=1e-9, atol=1e-9):
            failures.append(
                f"{notes}[{i}] = {note!r}: got {float(hz[i])!r}, "
                f"expected {exp!r} (deviation {cents:+d} cents must be preserved)"
            )
    if hz[0] == hz[1]:
        failures.append(
            f"{notes}: entries {hz[0]!r} and {hz[1]!r} are identical -- "
            f"the deviated note was quantized to its plain counterpart"
        )
    else:
        print("ok  {:25s} -> {}".format(str(notes), [float(v) for v in hz]))

if failures:
    print("\nFAILED:")
    for f in failures:
        print("  " + f)
    raise SystemExit(1)
print(f"\nall {len(CASES)} list inputs converted elementwise with deviations intact")