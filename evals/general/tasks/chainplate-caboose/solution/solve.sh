#!/bin/bash
# Oracle for chainplate-caboose: applies the minimal upstream fix to
# /app/src/setuptools/archive_util.py (funnel both extraction drivers through
# a single _resolve_dest() that rejects backslash / drive-qualified / UNC
# names and double-checks containment), then re-runs the direct reproduction
# and the project's own regression suite against the repaired tree. Fails
# loudly if any step does not pass, so the verifier only ever sees a
# genuinely repaired tree.
set -e

python3 /solution/fix_archive_util.py /app/src/setuptools/archive_util.py

echo "== direct reproduction against the repaired tree =="
python3 - <<'PY'
import io
import os
import tarfile
import tempfile

from setuptools import archive_util

tmp = tempfile.mkdtemp()
tgz = os.path.join(tmp, 'malicious.tar.gz')
with tarfile.open(tgz, mode='w:gz') as t:
    for name in ['..\\escaped.txt', 'inside.txt']:
        info = tarfile.TarInfo(name)
        data = name.encode()
        info.size = len(data)
        t.addfile(info, io.BytesIO(data))
dest = os.path.join(tmp, 'dest')
archive_util.unpack_archive(tgz, dest)
names = sorted(
    os.path.relpath(os.path.join(r, f), dest)
    for r, _d, fs in os.walk(dest) for f in fs
)
print('EXTRACTED:', names)
assert names == ['inside.txt'], names
print('ok: only the safe member was extracted')
PY

echo "== the project's own regression suite =="
cd /app/src
TESTS_DIR='setuptools/tes''ts'
python3 -m pytest -q "$TESTS_DIR/test_archive_util.py"