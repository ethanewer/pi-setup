#!/bin/bash
# Hidden case: a wildcard-adjacent COMPOSED rule must exclude a file whose
# on-disk name is DECOMPOSED. The upstream regression tests only match full
# exact names; here the non-ASCII literal is followed by a wildcard
# ('café-v1.rst' excluded by 'café*.rst').
set -u
cd "$(dirname "$0")"
python3 - <<'PY'
import unicodedata
from setuptools.command.egg_info import FileList

nfd = unicodedata.normalize('NFD', 'café-v1.rst')   # e + combining acute
nfc = unicodedata.normalize('NFC', 'café-v1.rst')   # single é code point
assert nfc != nfd, 'expected distinct byte forms'

fl = FileList()
fl.files = ['doc/' + nfd]
fl.exclude('doc/café*.rst')                          # composed rule, wildcard suffix
assert 'doc/' + nfd not in fl.files, \
    'exclude with wildcard left the decomposed-name file in the list'
print('case-ok')
PY