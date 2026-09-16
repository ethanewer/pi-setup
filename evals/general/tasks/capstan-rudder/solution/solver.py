#!/usr/bin/env python3
"""Oracle solver for capstan-rudder.

Applies the four minimal guards of the upstream fix to
librosa/core/convert.py in the checked-out tree at /app/src:
  * note_to_midi("") returns np.nan instead of raising ParameterError;
  * midi_to_note, midi_to_svara_h and midi_to_svara_c return the empty
    string for any non-finite MIDI value (NaN, +inf, -inf) instead of
    crashing in an integer conversion.

The rest of the module is left byte-identical, so the working-tree diff
against the pinned parent commit is exactly one source file.
"""
import sys
from pathlib import Path

path = Path("/app/src/librosa/core/convert.py")
text = path.read_text()

if "if not np.isfinite(midi)" in text:
    # The guards are already present (idempotent re-run); nothing to do.
    print("ok: non-finite guards already present in librosa/core/convert.py")
    sys.exit(0)

EDITS = []

# 1. note_to_midi: the empty string maps to np.nan
old = (
    '    if not isinstance(note, str):\n'
    '        return np.array([note_to_midi(n, round_midi=round_midi) for n in note])\n'
)
new = old + '\n    if note == "":\n        return np.nan\n'
EDITS.append(("note_to_midi empty-string guard", old, new))

# 2. midi_to_note: non-finite MIDI numbers map to ""
old = '        raise ParameterError("Cannot encode cents without octave information.")\n'
new = old + '\n    if not np.isfinite(midi):  # type: ignore\n        return ""\n'
EDITS.append(("midi_to_note non-finite guard", old, new))

# 3. midi_to_svara_h: non-finite MIDI numbers map to ""
old = '    SVARA_MAP = [\n'
new = '    if not np.isfinite(midi):\n        return ""\n\n    SVARA_MAP = [\n'
EDITS.append(("midi_to_svara_h non-finite guard", old, new))

# 4. midi_to_svara_c: non-finite MIDI numbers map to ""
old = '    svara_num = int(np.round(midi - Sa))\n'
new = '    if not np.isfinite(midi):\n        return ""\n\n    svara_num = int(np.round(midi - Sa))\n'
EDITS.append(("midi_to_svara_c non-finite guard", old, new))

for name, old, new in EDITS:
    n = text.count(old)
    if n != 1:
        print("ERROR: anchor for %s found %s times; aborting (no changes written)"
              % (name, n), file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text)
print("ok: four guards applied to /app/src/librosa/core/convert.py")