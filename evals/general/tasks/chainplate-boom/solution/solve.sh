#!/bin/bash
# Oracle for chainplate-boom: applies the terminal-safe binarization to the
# NLTK checkout (/app/src), re-runs the issue's reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_cnf.py /app/src/nltk/tree/transforms.py

echo "== probe output after the fix =="
python3 /app/probe_cnf.py

echo "== upstream regression tests =="
cd /app/src
python3 -m pytest /opt/golden/test_treetransforms.py -q -p no:cacheprovider