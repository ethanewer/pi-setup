#!/bin/bash
# Oracle for chainplate-fathom: applies the minimal upstream fix to
# cli/src/semgrep/git.py (route get_project_url() through a new
# clean_project_url() that strips the userinfo part of the remote URL),
# then demonstrates the fix end to end and runs the project's own
# regression test and its existing git-module unit test against the
# repaired tree.
set -e

python3 /solution/fix_git.py

echo
echo "== reproduction: get_project_url() after the fix =="
python3 - <<'EOF'
import os
import subprocess
import tempfile

from semgrep.git import get_project_url

url = "https://gitlab-ci-token:glcbt-64_wFuiRFQk9t841JHKQnAT@gitlab.company.world/app/test-case.git"
d = tempfile.mkdtemp(prefix="pubdemo-")
subprocess.check_call(["git", "init", "-q", d])
subprocess.check_call(["git", "remote", "add", "origin", url], cwd=d)
old = os.getcwd()
try:
    os.chdir(d)
    got = get_project_url()
finally:
    os.chdir(old)
print("get_project_url() ->", got)
assert got == "https://gitlab.company.world/app/test-case.git", got
print("ok: credentials stripped, host and path kept")
EOF

echo
echo "== the project's own regression test for this bug =="
cd /app/src/cli
python3 -m pytest -p no:cacheprovider -q /opt/golden/test_clean_project_url.py

echo
echo "== the project's existing unit test for the git module =="
cd /app/src/cli
python3 -m pytest -p no:cacheprovider -q tests/unit/test_baseline.py