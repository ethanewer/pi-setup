#!/usr/bin/env python3
"""Hidden case B: vectorised (array / list) inputs across the fixed family.

The upstream regression tests only pass scalars. These vectors push the same
guards through the numba-vectorised array path of midi_to_note /
midi_to_svara_h / midi_to_svara_c and through the recursive list path of
note_to_midi, with the non-finite entries interleaved among finite ones. At
the parent commit every whole-call raises; at the fixed commit each must
return an array in which exactly the non-finite entries hold the sentinel.
"""
import numpy as np
import librosa
import librosa.core.convert  # noqa: F401  (lazy_loader >= 0.4 workaround)


def main():
    # ---- midi_to_note on an array with non-finite entries interleaved ------
    notes = librosa.midi_to_note(np.array([60.0, np.nan, np.inf, -np.inf, 69.0]))
    assert notes.shape == (5,)
    assert notes[0] == "C4" and notes[4] == "A4"
    assert (notes[1:4] == "").all()

    # ---- midi_to_svara_h on an array ---------------------------------------
    svh = librosa.midi_to_svara_h(np.array([60.0, np.nan, 65.0]), Sa=60)
    assert svh.shape == (3,)
    assert svh[0] == "S" and svh[2] == "m" and svh[1] == ""

    # ---- midi_to_svara_c on an array (Carnatic, mela=22) --------------------
    svc = librosa.midi_to_svara_c(np.array([61.0, -np.inf, 62.0]), Sa=60, mela=22)
    assert svc.shape == (3,)
    assert svc[1] == "" and svc[0] != "" and svc[2] != ""

    # ---- note_to_midi on a list with an empty entry -------------------------
    midi = librosa.note_to_midi(["C4", "", "D4"])
    assert midi.shape == (3,)
    assert midi[0] == 60 and midi[2] == 62 and np.isnan(midi[1])

    # ---- hz_to_note on an array (round trip through hz_to_midi) -------------
    hz = librosa.hz_to_note(np.array([440.0, np.nan, 880.0]))
    assert hz.shape == (3,)
    assert hz[0] == librosa.hz_to_note(440.0)
    assert hz[2] == librosa.hz_to_note(880.0)
    assert hz[1] == ""

    print("ok: hidden case vectorized (%d assertions)" % 17)


if __name__ == "__main__":
    main()