#!/bin/bash
# Hidden case: END-TO-END sdist build. A real packaging project whose
# MANIFEST.in says 'global-include *.txt' plus 'global-exclude café.txt'
# (COMPOSED) while the file sits on disk under its DECOMPOSED name must
# produce an sdist archive that does NOT contain the file. On the unfixed
# tree the archive contains it (the leak the bug causes); after the fix it
# must be gone. Built with the INSTALLED (editable, i.e. the fixed) setuptools
# via `setup.py sdist` directly - no build isolation, no network.
set -u
cd "$(dirname "$0")"
python3 - <<'PY'
import os, shutil, subprocess, sys, tarfile, tempfile, unicodedata

nfc = unicodedata.normalize('NFC', 'café.txt')
nfd = unicodedata.normalize('NFD', 'café.txt')
assert nfc != nfd

root = tempfile.mkdtemp(prefix='br-sdist-')
old = os.getcwd()
try:
    with open(os.path.join(root, 'setup.py'), 'w', encoding='utf-8') as f:
        f.write("from setuptools import setup\n"
                "setup(name='demo', version='0.1', py_modules=['demo'])\n")
    with open(os.path.join(root, 'demo.py'), 'w', encoding='utf-8') as f:
        f.write("VALUE = 1\n")
    with open(os.path.join(root, 'MANIFEST.in'), 'w', encoding='utf-8') as f:
        f.write("global-include *.txt\n"
                "global-exclude %s\n" % nfc)
    with open(os.path.join(root, nfd), 'w', encoding='utf-8') as f:
        f.write("should-not-ship\n")

    os.chdir(root)
    res = subprocess.run([sys.executable, 'setup.py', 'sdist'],
                         capture_output=True, text=True,
                         env=dict(os.environ))
    os.chdir(old)
    if res.returncode != 0:
        sys.stderr.write((res.stderr or '')[-4000:])
        sys.stderr.write((res.stdout or '')[-1000:])
        raise SystemExit('sdist build failed')

    sdists = [f for f in os.listdir(os.path.join(root, 'dist'))
              if f.endswith('.tar.gz')]
    assert len(sdists) == 1, sdists
    with tarfile.open(os.path.join(root, 'dist', sdists[0])) as tf:
        names = tf.getnames()
    leaked = [n for n in names
              if unicodedata.normalize('NFC', os.path.basename(n)) == nfc]
    assert not leaked, 'excluded file leaked into sdist archive: %r' % (leaked,)
    print('case-ok')
finally:
    os.chdir(old)
    shutil.rmtree(root, ignore_errors=True)
PY