#!/bin/bash
# Oracle for ballast-pilot: applies the RIBES empty-input guards to the NLTK
# checkout (/app/src), sanity-checks the reproduction, and runs the upstream
# regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_ribes.py /app/src/nltk/translate/ribes_score.py

echo "== probe output after the fix =="
python3 /app/probe_ribes.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_ribes.py -q -p no:cacheprovider