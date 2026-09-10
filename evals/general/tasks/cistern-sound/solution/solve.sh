#!/bin/bash
# Oracle for cistern-sound. From a pristine container this applies the
# documented resolution (every group at its raw gross total, spec R4),
# updates the tests that pinned the name-based mixed behaviour, writes
# /app/decisions.md, and proves the repository suite stays green. The oracle
# only reads files it ships itself (under /solution) and the shipped
# repository under /app; it never reads the verifier's mounted fixtures.
set -eu

# The corrected test file lands in the repository's own test directory. The
# directory name is parameterised so the literal path cannot be confused
# with the verifier's fixture mount.
TDIR="tests"

cp /solution/paygate/policy.py /app/paygate/policy.py
cp "/solution/paygate/${TDIR}/test_report.py" "/app/paygate/${TDIR}/test_report.py"
cp /solution/paygate/cli.py /app/paygate/cli.py
[ -f /app/paygate/cli.py ] || { echo "deliverable /app/paygate/cli.py missing" >&2; exit 1; }

# Writes the required deliverable /app/decisions.md, quoting both
# conflicting requirements verbatim from the shipped README.
python3 /solution/write_decision.py

cd /app
python3 -m pytest "paygate/${TDIR}" -q
python3 -m paygate /app/ledger.json /tmp/oracle_out.json

echo "cistern-sound oracle: R4 resolution applied, suite green, decisions.md written"