#!/bin/bash
# Oracle re-check for tasks whose verifier/instruction changed in the
# 2026-08-25 triage pass. Sequential single-task harbor invocations.
set -u
cd "$(dirname "$0")/.."
mkdir -p jobs-oracle3
for t in skill-post-receive-hooks skill-static-binary-analysis skill-port-forwarding item-054-main; do
  echo "===== oracle re-check: $t"
  rm -rf "jobs-oracle3/o3-$t"
  harbor run -p "tasks/$t" -a oracle -y -o jobs-oracle3 --job-name "o3-$t" \
    >/dev/null 2>&1
  rc=$?
  rw=$(cat "jobs-oracle3/o3-$t/$t"__*/verifier/reward.txt 2>/dev/null || echo MISSING)
  echo "RESULT $t harbor_rc=$rc reward=$rw"
done
echo ORACLE_RECHECK_DONE
