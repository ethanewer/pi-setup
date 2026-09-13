#!/usr/bin/env python3
"""Hidden case 3 (ballast-keel): the equal-tempered quantization path stays
available via round_midi=True, and the default and round_midi=False agree.

The regression suite checks np.isclose(note_to_hz(n, round_midi=False),
note_to_hz(n)) for one note; these cases pin the contract across more notes.
The quantization contract is defined exactly as the library defines it:
round_midi=True quantizes the MIDI number (banker's rounding, int(np.round))
before converting -- so for e.g. 'A4-50' (midi 68.5) it lands on midi 68, not
on the spelling of the plain note. The default call must *not* quantize at
all: it must equal the explicit round_midi=False result and differ from the
quantized one.
"""
from __future__ import annotations

import numpy as np
import librosa


def midi_of(note: str) -> float:
    """Equal-tempered MIDI number of the plain note with its deviation
    removed, computed from the spellings (C4=60, A4=69, semitone offsets)."""
    stem = note
    import re as _re

    stem = _re.sub(r"[+-]\d+$", "", stem)
    return float(librosa.note_to_midi(stem))


def cents_of(note: str) -> float:
    import re as _re

    m = _re.search(r"([+-])(\d+)$", note)
    if not m:
        return 0.0
    return (1.0 if m.group(1) == "+" else -1.0) * int(m.group(2))


NOTES = ["C2-30", "A4-50", "A4+50", "G#3+12", "Eb4-25", "F2-37", "Bb2-25"]

failures = []
# 1. default == explicit round_midi=False, i.e. deviations preserved by default
for note in NOTES:
    default = librosa.note_to_hz(note)
    explicit = librosa.note_to_hz(note, round_midi=False)
    if not np.isclose(default, explicit, rtol=1e-12, atol=1e-12):
        failures.append(
            f"{note}: default {float(default)!r} != round_midi=False "
            f"{float(explicit)!r} (default must preserve the cents deviation)"
        )
    else:
        print(f"ok  {note:8s} default == round_midi=False = {float(default):.6f} Hz")

# 2. round_midi=True quantizes the midi number before conversion; the result
#    must differ from the default (deviated) result for every deviated note
for note in NOTES:
    cents = cents_of(note)
    midi = midi_of(note)
    q_midi = int(np.round(midi + cents / 100.0))
    q_exp = 440.0 * 2.0 ** ((q_midi - 69.0) / 12.0)
    q = librosa.note_to_hz(note, round_midi=True)
    if not np.isclose(q, q_exp, rtol=1e-12, atol=1e-12):
        failures.append(
            f"{note}: round_midi=True {float(q)!r} != quantized {q_exp!r} "
            f"(midi {q_midi})"
        )
    if cents != 0 and np.isclose(q, librosa.note_to_hz(note), rtol=1e-12, atol=1e-12):
        failures.append(f"{note}: round_midi=True equals the default deviated result")
    else:
        print(f"ok  {note:8s} round_midi=True quantizes to midi {q_midi} = {float(q):.6f} Hz")

# 3. scalar/array shape contract preserved
s = librosa.note_to_hz("A4-50")
a = librosa.note_to_hz(["A4-50"])
if np.ndim(s) != 0:
    failures.append(f"scalar input: expected 0-d result, got shape {np.shape(s)}")
if np.shape(a) != (1,):
    failures.append(f"list input: expected shape (1,), got {np.shape(a)}")
if not np.isclose(float(s), float(a[0])):
    failures.append(f"scalar {float(s)!r} and list {float(a[0])!r} disagree")

if failures:
    print("\nFAILED:")
    for f in failures:
        print("  " + f)
    raise SystemExit(1)
print("\nall round_midi contract checks passed")