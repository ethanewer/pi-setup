#!/bin/bash
# Oracle for capstan-rudder: apply the functional part of the upstream fix
# (librosa/librosa issue #1944) to the checked-out tree at /app/src, then
# prove the fix from the repaired tree with the reproduction snippet.
set -u
python3 /solution/solver.py
python3 - <<'EOF'
import numpy as np
import librosa
import librosa.core.convert  # lazy_loader >= 0.4: load ahead of use

assert librosa.midi_to_note(np.nan) == ""
assert librosa.midi_to_note(np.inf) == ""
assert librosa.midi_to_note(-np.inf) == ""
assert np.isnan(librosa.note_to_midi(""))
print("PASS")
EOF