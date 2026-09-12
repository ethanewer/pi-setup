#!/bin/bash
# cistern-forge verifier.
#
# The agent's deliverable is the repaired upstream checkout at /app/src: the
# selector-based socket wait loop (psycopg.waiting.wait_selector) must survive
# a generator that waits twice on the same connection (e.g. connect: first
# writable, then readable) instead of dying with
# 'KeyError: ... is already registered'. Grading order:
#
#   1. provenance (tests/provenance_check.py): repository still at the pinned
#      parent revision, upstream fix/regression commits absent from the object
#      store, the only tracked change is the one library source file the fix
#      requires (and it IS changed), no stray untracked files, and the
#      installed psycopg resolves into /app/src.
#   2. golden regression: the fix-branch version of tests/test_waiting.py (the
#      'nevents' parametrization, commit 5369bbc9, extracted at image build
#      into /opt/golden from a deleted scratch clone, so the fix is not
#      reachable in /app/src) is swapped over the repo copy and the whole
#      wait_selector slice of test_wait_r must pass -- 16 tests, of which the
#      four nevents=2/ready=R combos are exactly the ones that FAIL at the
#      unfixed parent with KeyError.
#   3. the project's own untouched waiting test (restored old form, all
#      wait functions) must still pass, proving the fix broke nothing else.
#   4. three authored hidden cases (tests/hidden/h{1,2,3}) exercise the same
#      code path from inputs the upstream test does not use: a changing wait
#      mask (EVENT_WRITE then EVENT_READ) on a socketpair, the same flow over
#      a real TCP connect, and a three-phase mixed-mask wait at interval 0.
# Any failure -> reward 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "cistern-forge FAIL: $1" >&2; ok=0; }

export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}

# --- 1. provenance -----------------------------------------------------------
if [ $ok -eq 1 ]; then
  python3 /tests/provenance_check.py || fail "provenance checks failed"
fi

# --- 2. golden upstream regression test --------------------------------------
# Swap the fix-branch test file over the repo's untouched copy, then run the
# project's own test runner on the wait_selector slice of test_wait_r.
if [ $ok -eq 1 ]; then
  cp /opt/golden/test_waiting.py /app/src/tests/test_waiting.py \
    || fail "could not copy the golden test into the checkout"
  cp /opt/golden/test_waiting_async.py /app/src/tests/test_waiting_async.py \
    || fail "could not copy the golden async test into the checkout"
  (cd /app/src && python3 -m pytest "tests/test_waiting.py::test_wait_r" -k wait_selector -q) \
    > /tmp/cf-golden.log 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then
    tail -60 /tmp/cf-golden.log >&2
    fail "golden regression test failed (rc=$rc)"
  elif ! grep -q "16 passed" /tmp/cf-golden.log; then
    tail -60 /tmp/cf-golden.log >&2
    fail "golden regression test did not report 16 passed"
  fi
fi

# --- 3. project's own untouched suite subset (proves no regression) ----------
if [ $ok -eq 1 ]; then
  (cd /app/src && git checkout -q -- tests/test_waiting.py tests/test_waiting_async.py) \
    || fail "could not restore the repository test files"
  (cd /app/src && python3 -m pytest "tests/test_waiting.py::test_wait_r" -q) \
    > /tmp/cf-suite.log 2>&1 \
    || { tail -40 /tmp/cf-suite.log >&2; fail "existing upstream suite subset failed"; }
fi

# --- 4. authored hidden cases (same path, inputs upstream does not use) -------
if [ $ok -eq 1 ]; then
  for c in h1 h2 h3; do
    (cd /tmp && python3 "/tests/hidden/$c/check.py") \
      || fail "hidden-$c behavioural check failed"
  done
fi

[ $ok -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "cistern-forge reward=$reward" >&2
exit 0