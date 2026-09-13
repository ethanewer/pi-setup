#!/bin/bash
# Oracle for ballast-keel: applies the minimal upstream fix to the librosa
# checkout at /app/src (give note_to_hz a keyword-only round_midi parameter
# defaulting to False and forward it to note_to_midi, so cents tuning
# deviations are preserved by default), then proves the fix with the exact
# issue reproduction and with the project's own test suite.
set -e

python3 /solution/fix_convert.py /app/src/librosa/core/convert.py

echo "== issue reproduction: note_to_hz must preserve the -30 cent deviation =="
cd /app/src && python3 -c "
import librosa
h = librosa.note_to_hz('C2-30')
print('note_to_hz(C2-30) =', repr(h), ' note_to_hz(C2) =', repr(librosa.note_to_hz('C2')))
assert h != librosa.note_to_hz('C2')
assert h == librosa.note_to_hz('C2-30', round_midi=False)
assert librosa.note_to_hz('C2-30', round_midi=True) == librosa.note_to_hz('C2')
print('ok: deviations preserved by default, quantization available on request')
"

# lazy_loader >= 0.4 can break pytest collection of the tree's own tests
# ('No librosa.core attribute convert'); run pytest through a wrapper that
# pre-imports librosa.core.convert in the same process.
echo "== the project's own existing test suite (tests/test_convert.py) =="
cd /app/src && python3 -c "import sys, librosa.core.convert, pytest; sys.exit(pytest.main(list(sys.argv[1:])))" tests/test_convert.py -o addopts= -p no:cacheprovider -q