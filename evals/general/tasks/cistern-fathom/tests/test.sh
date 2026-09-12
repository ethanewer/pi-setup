#!/bin/bash
# cistern-fathom verifier.
#
# The agent's deliverable is the repaired upstream checkout at /app/src: the
# TypeConversionDict.get() family must absorb converter failures (TypeError as
# well as ValueError) and return the supplied default. Grading order:
#
#   1. provenance (tests/provenance_check.py): repository still at the pinned
#      parent revision, upstream fix commit absent from the object store, the
#      only tracked change is the one library source file the fix requires
#      (and it IS changed), no stray untracked files inside the tree.
#   2. golden regression: the fix-commit version of tests/test_datastructures.py
#      (extracted at image build into /opt/golden from a deleted scratch clone,
#      so the fix is not reachable in /app/src) is swapped over the repo copy
#      and must pass. At the unfixed parent this is the test that FAILS.
#   3. the project's own untouched suite subset (test_urls.py,
#      test_security.py) must still pass, proving the fix broke nothing else.
#   4. three authored hidden cases (tests/hidden/h{1,2,3}) exercise the same
#      code path from inputs the upstream test does not use.
# Any failure -> reward 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "cistern-fathom FAIL: $1" >&2; ok=0; }

export PYTHONPATH=/app/src/src${PYTHONPATH:+:$PYTHONPATH}
# Run the hidden behavioural checks in a wrapper-free interpreter (-S skips
# site.py, so no sitecustomize/usercustomize/.pth interceptor can fake the
# repair): extend PYTHONPATH with the true site-packages dir so the direct
# imports in the check scripts still resolve (markupsafe lives there).
SP=$(python3 -c "import site; print(site.getsitepackages()[0])")
export PYTHONPATH=${PYTHONPATH}:${SP}

# --- 1. provenance -----------------------------------------------------------
if [ $ok -eq 1 ]; then
  python3 /tests/provenance_check.py || fail "provenance checks failed"
fi

# --- 2. golden upstream regression test --------------------------------------
# Swap the fix-commit test file over the repo's untouched copy, then run the
# project's own test runner on it.
if [ $ok -eq 1 ]; then
  cp /opt/golden/test_datastructures.py /app/src/tests/test_datastructures.py \
    || fail "could not copy the golden test into the checkout"
  (cd /app/src && python3 -m pytest -q tests/test_datastructures.py) \
    > /tmp/cf-golden.log 2>&1 \
    || { tail -30 /tmp/cf-golden.log >&2; fail "golden regression test failed"; }
fi

# --- 3. project's own suite subset (proves no regression) ---------------------
if [ $ok -eq 1 ]; then
  (cd /app/src && python3 -m pytest -q tests/test_urls.py tests/test_security.py) \
    > /tmp/cf-suite.log 2>&1 \
    || { tail -30 /tmp/cf-suite.log >&2; fail "existing upstream suite subset failed"; }
fi

# --- 4. authored hidden cases (same path, inputs upstream does not use) -------
if [ $ok -eq 1 ]; then
  for c in h1 h2 h3; do
    (cd /tmp && python3 -S "/tests/hidden/$c/check.py") \
      || fail "hidden-$c behavioural check failed"
  done
fi

[ $ok -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "cistern-fathom reward=$reward" >&2
exit 0