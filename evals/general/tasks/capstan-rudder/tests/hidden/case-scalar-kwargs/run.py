#!/usr/bin/env python3
"""Hidden case A: scalar and keyword-argument variants of the non-finite guards.

The upstream regression tests (test_midi_to_note_empty, ...) only pass plain
numpy floats with default keyword arguments to the four fixed entry points.
These vectors instead use non-default dtypes (float32), keyword combinations
(octave=, cents=, key=, unicode=, abbr=), a custom Sa and a different mela,
and the hz_to_note round trip -- inputs the upstream tests do not use. At the
parent commit every non-finite vector raises; at the fixed commit each must
return the sentinel, and finite/named inputs must keep converting exactly.
"""
import numpy as np
import librosa
import librosa.core.convert  # noqa: F401  (lazy_loader >= 0.4 workaround)


def main():
    # ---- midi_to_note: non-default dtypes and keyword combinations ----------
    assert librosa.midi_to_note(np.float32(np.nan)) == ""
    assert librosa.midi_to_note(np.float32(-np.inf)) == ""
    assert librosa.midi_to_note(np.float64(np.inf), octave=False) == ""
    assert librosa.midi_to_note(np.inf, cents=True, octave=True) == ""
    assert librosa.midi_to_note(np.nan, key="F:min", unicode=False) == ""
    assert librosa.midi_to_note(np.nan, key="C:maj", unicode=True, cents=False) == ""

    # ---- hz_to_note round trip (feeds midi_to_note through hz_to_midi) ------
    assert librosa.hz_to_note(np.nan) == ""
    assert librosa.hz_to_note(-np.inf) == ""
    assert librosa.hz_to_note(np.inf) == ""

    # ---- svara variants: custom Sa, custom mela, long/short spellings -------
    assert librosa.midi_to_svara_h(np.nan, Sa=60.0) == ""
    assert librosa.midi_to_svara_h(np.inf, Sa=65.5, abbr=False) == ""
    assert librosa.midi_to_svara_h(-np.inf, Sa=60, abbr=True, octave=False, unicode=False) == ""
    assert librosa.midi_to_svara_c(np.nan, Sa=60, mela=8) == ""
    assert librosa.midi_to_svara_c(np.inf, Sa=69, mela=29, abbr=False) == ""

    # ---- sanity: finite / named inputs still convert exactly ----------------
    assert librosa.midi_to_note(60) == "C4"
    assert librosa.midi_to_note(69) == "A4"
    assert librosa.midi_to_note(37, unicode=False) == "C#2"
    assert librosa.midi_to_svara_h(65, Sa=60) == "m"
    assert librosa.note_to_midi("C4") == 60
    assert librosa.note_to_midi("A4") == 69

    print("ok: hidden case scalar-kwargs (%d assertions)" % 24)


if __name__ == "__main__":
    main()