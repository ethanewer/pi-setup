#!/bin/bash
# Oracle for bracket-quay: repair the quaydoc anchor regression by applying
# the real fix, verifying it, and writing the postmortem that names the
# commit which introduced it.  Does the actual work in /app/quayside; never
# reads /tests.
set -euo pipefail

cd /app/quayside
python3 /solution/fix_quaydoc.py

# deliverable check: the postmortem must exist and name a commit
test -f /app/postmortem.md
grep -Eq '^Introduced by commit [0-9a-f]{40}$' /app/postmortem.md

echo "oracle complete: /app/quayside repaired, /app/postmortem.md written"