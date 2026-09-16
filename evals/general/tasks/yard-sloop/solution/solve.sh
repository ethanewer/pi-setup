#!/bin/bash
# Oracle for yard-sloop: applies the real fix (keep the /_git segment in
# Azure DevOps project URLs) to the semgrep checkout at /app/src, reconciles
# the project's own tracked regression test with the corrected behaviour,
# writes the /app/reproduce.py deliverable, then proves all of it.
set -e

python3 /solution/fix_semgrep.py

echo "== reproduction (should print the corrected url and exit 0) =="
python3 /app/reproduce.py

echo "== project's own regression test, from the repaired tree =="
cd /app/src/cli
python3 -m pytest tests/default/e2e-pro/test_meta.py -q -p no:cacheprovider

python3 -m pytest tests/default/unit/test_clean_project_url.py tests/default/unit/test_bytesize.py tests/default/unit/test_semver_matching.py -q -p no:cacheprovider

echo "== project's regression test from the authoritative copy =="
python3 -m pytest /opt/golden/test_meta.py -q -p no:cacheprovider