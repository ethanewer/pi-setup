#!/bin/bash
# Oracle for cistern-cable: applies the upstream fix for issue #2998 to the
# httpx checkout (/app/src), sanity-checks the reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_textchunker.py /app/src/httpx/_decoders.py

echo "== probe output after the fix =="
python3 /app/probe_iter_text.py

echo "== upstream regression test =="
cd /app/src
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest /opt/golden/test_decoders.py::test_streaming_text_decoder \
    -q -p no:cacheprovider