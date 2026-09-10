#!/usr/bin/env bash
# Oracle for hopper-ledge: repair the shared CI runner.
#
# The repository ships a buggy ci/runner.py with three independent defects
# (artifact downloads land in a nested dir instead of the consumer workspace
# root; the dependency cache is snapshotted at restore time, before the install
# step populates it, so the warm run restores an empty cache and skips a
# needed install; all jobs share one workspace checkout, so build output leaks
# into the test job and trips the repo-hygiene test). The fix is to replace the
# runner with the corrected generic implementation and then prove the
# cold/warm two-run contract locally.
set -euo pipefail

cp /solution/fixed_runner.py /app/repo/ci/runner.py
chmod 755 /app/repo/ci/runner.py

# Prove the fix exactly as the verifier will: cold run, then a warm run over
# the same cache dir with a fresh work root.
rm -rf /tmp/oracle-work /tmp/oracle-cache /tmp/oracle-s1.json /tmp/oracle-s2.json

python3 /app/repo/ci/runner.py \
    --pipeline /app/repo/ci/pipeline.json \
    --repo /app/repo \
    --work-root /tmp/oracle-work --cache-dir /tmp/oracle-cache \
    --summary /tmp/oracle-s1.json

rm -rf /tmp/oracle-work

python3 /app/repo/ci/runner.py \
    --pipeline /app/repo/ci/pipeline.json \
    --repo /app/repo \
    --work-root /tmp/oracle-work --cache-dir /tmp/oracle-cache \
    --summary /tmp/oracle-s2.json

echo "oracle: pipeline green on a cold run and on a warm run"