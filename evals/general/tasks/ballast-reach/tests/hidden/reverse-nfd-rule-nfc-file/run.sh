#!/bin/bash
# Hidden case: the REVERSE rule direction through FileList — a rule authored
# DECOMPOSED (a MANIFEST.in line produced on macOS, say) must exclude a file
# whose on-disk name is stored COMPOSED, with a different base character
# (ï, i + U+0308) than the upstream tests use (é). Upstream only exercises
# the composed-rule / decomposed-file direction at the FileList level.
set -u
cd "$(dirname "$0")"
python3 - <<'PY'
import unicodedata
from setuptools.command.egg_info import FileList

nfd_rule = unicodedata.normalize('NFD', 'naïve.txt')  # i + combining diaeresis
nfc_file = unicodedata.normalize('NFC', 'naïve.txt')  # single ï code point
assert nfd_rule != nfc_file, 'expected distinct byte forms'

fl = FileList()
fl.files = [nfc_file]
fl.global_exclude(nfd_rule)
assert nfc_file not in fl.files, \
    'decomposed rule did not exclude the composed-name file'
print('case-ok')
PY