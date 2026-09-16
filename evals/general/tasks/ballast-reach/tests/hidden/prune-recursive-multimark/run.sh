#!/bin/bash
# Hidden case: directory-level rules on a MULTI-DIACRITIC name. A COMPOSED
# prune rule and a COMPOSED recursive-exclude rule over a DECOMPOSED
# directory tree ('Ångström' = Å + ö, two different base characters and two
# different combining marks). Upstream only exercises global-exclude on
# files.
set -u
cd "$(dirname "$0")"
python3 - <<'PY'
import os
import unicodedata
from setuptools.command.egg_info import FileList

nfd_dir = unicodedata.normalize('NFD', 'Ångström')
nfc_dir = unicodedata.normalize('NFC', 'Ångström')
assert nfd_dir != nfc_dir, 'expected distinct byte forms'

# prune: a composed rule must drop every entry under the decomposed dir
fl = FileList()
fl.files = [
    os.path.join(nfd_dir, 'notes', 'archiv.txt'),
    os.path.join(nfd_dir, 'index.txt'),
]
fl.prune(nfc_dir)
assert all(not f.startswith(nfd_dir) for f in fl.files), \
    'prune leaked files from the decomposed directory'

# recursive-exclude: same shape, nested file under the decomposed dir
fl2 = FileList()
fl2.files = [os.path.join(nfd_dir, 'notes', 'bericht.txt')]
fl2.recursive_exclude(nfc_dir, 'bericht.txt')
assert os.path.join(nfd_dir, 'notes', 'bericht.txt') not in fl2.files, \
    'recursive-exclude leaked a file'
print('case-ok')
PY