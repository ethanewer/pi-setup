#!/usr/bin/env python3
"""Hidden case 1 (ballast-keel): note_to_hz must preserve cents tuning
deviations by default for single-note string inputs.

Every expectation is computed from the independent formula
    hz = 440.0 * 2.0 ** ((midi + cents/100 - 69.0) / 12.0)
where ``midi`` is the equal-tempered MIDI number of the plain note name
(librosa convention: C4=60, A4=69) and ``cents`` is the deviation.
The upstream regression test only uses the single input 'C2-30'; these
inputs use different notes, deviations, accidentals (sharp and flat),
and octaves.
"""
from __future__ import annotations

import numpy as np
import librosa


def expected(note_midi: float, cents: float) -> float:
    return 440.0 * 2.0 ** ((note_midi + cents / 100.0 - 69.0) / 12.0)


# (spelled note, plain-note equal-tempered midi, cents deviation)
CASES = [
    ("A4-50", 69, -50),
    ("A4+50", 69, +50),
    ("C2-30", 36, -30),
    ("G#3+12", 56, +12),
    ("Eb4-25", 63, -25),
    ("F2-37", 41, -37),
    ("Bb2-25", 46, -25),
    ("F#5+8", 78, +8),
]

failures = []
for note, midi, cents in CASES:
    hz = librosa.note_to_hz(note)
    exp = expected(midi, cents)
    same_as_plain = float(hz) == float(librosa.note_to_hz(note.rstrip("+-0123456789")))
    if not np.isclose(hz, exp, rtol=1e-9, atol=1e-9):
        failures.append(
            f"{note}: got {float(hz)!r}, expected {exp!r} "
            f"(note_to_hz must not discard the {cents:+d}-cent deviation)"
        )
    elif same_as_plain:
        failures.append(
            f"{note}: got {float(hz)!r}, which is identical to the plain note "
            f"frequency -- deviation discarded"
        )
    else:
        print(f"ok  {note:8s} -> {float(hz):.6f} Hz")

if failures:
    print("\nFAILED:")
    for f in failures:
        print("  " + f)
    raise SystemExit(1)
print(f"\nall {len(CASES)} deviated notes converted to their detuned frequency")