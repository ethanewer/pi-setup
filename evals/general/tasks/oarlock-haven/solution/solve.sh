#!/bin/bash
# Oracle for oarlock-haven: applies the upstream monkeypatch undo-bookkeeping
# fix to the pytest checkout at /app/src, creates the reproduction deliverable
# at /app/repro_failed_undo.py, re-runs the reproduction, and runs the
# project's own monkeypatch module plus the upstream regression test that was
# extracted at image build time into /opt/golden/.
set -e

python3 /solution/fix_monkeypatch.py /app/src/src/_pytest/monkeypatch.py
cp /solution/repro.py /app/repro_failed_undo.py
chmod a+rx /app/repro_failed_undo.py

echo "== reproduction after the fix =="
python3 /app/repro_failed_undo.py

echo "== project's own monkeypatch module (parent version) =="
cd /app/src
python3 -m pytest testing/test_monkeypatch.py -q -p no:cacheprovider

echo "== upstream regression test extracted from the fix commit =="
cp /opt/golden/test_monkeypatch.py testing/test_monkeypatch.py
python3 -m pytest testing/test_monkeypatch.py -q -p no:cacheprovider
git checkout -- testing/test_monkeypatch.py

echo "== oracle done =="