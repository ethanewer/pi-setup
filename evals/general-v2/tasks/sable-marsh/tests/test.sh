#!/bin/bash
# Verifier for sable-marsh (executes-deliverable). verify.py executes
# /app/fit_model.py on the visible and hidden datasets, loads the persisted
# /app/artifacts/model.joblib and freshly written models, and checks the
# scikit-learn linear-model serialization and coefficient-shape contract plus
# the manifest and accuracy floor. Writes the reward to
# /logs/verifier/reward.txt (1 all pass, 0 otherwise).
set -u
mkdir -p /logs/verifier
python3 /tests/verify.py > /tmp/verify_out.log 2>&1
cat /tmp/verify_out.log
reward="$(cat /logs/verifier/reward.txt 2>/dev/null || echo 0)"
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
