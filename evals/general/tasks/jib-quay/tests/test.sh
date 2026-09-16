#!/bin/bash
#
# jib-quay verifier.
#
# Executes the deliverables: (1) fixture integrity + deliverable-differs
# checks; (2) stdlib-only source check on /app/service.py; (3) content check
# on /app/diagnosis.md; (4) per hidden case: a NEGATIVE probe — the ORIGINAL
# shipped service (from /opt/pristine/, hash-checked) must still stall under
# the case's mix — and the graded STRESS harness — 10 concurrent iterations
# of the mix against the fixed deliverable, each bounded, asserting exact
# ledger-model results, an honored --latency step, and a concurrency floor
# (concurrent must beat serial by a wide margin: a single global lock or a
# single-threaded server fails this).
#
# Writes exactly 0 or 1 to /logs/verifier/reward.txt on every path.
set -u

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt
fail=0

check() {
  local name=$1; shift
  if ! "$@" > "/tmp/jq_${name}.log" 2>&1; then
    fail=1
    echo "FAIL $name:"
    sed 's/^/    /' "/tmp/jq_${name}.log"
  else
    echo "ok   $name: $(tail -1 "/tmp/jq_${name}.log")"
  fi
}

check fixtures   python3 /tests/stress.py fixtures
check imports    python3 /tests/stress.py imports /app/service.py
check diagnosis  python3 /tests/stress.py diagnosis /app/diagnosis.md

for case in case_oshkosh case_rajput case_cuthbert; do
  check "negative-$case" python3 /tests/stress.py probe-pristine \
        "/tests/hidden/$case" /opt/pristine/service.py 0.02
  check "stress-$case" python3 /tests/stress.py case-run \
        "/tests/hidden/$case" /app/service.py 0.02 10
done

if [ "$fail" = 0 ]; then
  echo "ALL PASS"
  echo 1 > /logs/verifier/reward.txt
else
  echo "SOME CHECKS FAILED"
  echo 0 > /logs/verifier/reward.txt
fi
exit 0