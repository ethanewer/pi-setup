#!/bin/bash
# Oracle for capstan-boom: applies the git URL parsing fix to the semgrep
# checkout (/app/src), re-runs the reproduction, and runs the upstream
# regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_git_url_parser.py /app/src/cli/src/semgrep/external/git_url_parser.py

echo "== reproduction output after the fix =="
python3 /app/probe_git_url.py

echo "== upstream regression test =="
cd /app/src/cli
python3 -m pytest "/opt/golden/test_meta.py::test_git_url_parser" \
                 "/opt/golden/test_meta.py::test_get_url_from_sstp_url" \
                 -o addopts="" -q -p no:cacheprovider

echo "== oracle done =="