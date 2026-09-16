#!/bin/bash
# Verifier for plinth-wicket.
#
# 1. Runs the project's OWN full jsdom suite in /app/src and requires all 1227
#    cases pass (proving no existing test was skipped, removed, weakened, or
#    broken, and that /app/src stayed at the upstream 3.4.15 state).
# 2. Runs the agent's /app/bypass-test.js (must exit 0).
# 3. Runs /app/sanitize.js against hidden style-attribute CSS mutation payloads
#    in /tests/hidden and requires sanitisation held while legitimate CSS and
#    ordinary DOMPurify stripping both survive.
#
# Binary reward 1 only when every stage passes. Writes /logs/verifier/reward.txt.
#
# Guarantee a reward on every exit path: a verifier that raises while grading
# the deliverable must still produce a scorable 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=1

if [ ! -f /app/sanitize.js ] || [ ! -f /app/bypass-test.js ]; then
  echo "FAIL: one or both deliverables missing under /app" >&2
  reward=0
fi

# --- 0. the /app/src clone must be pristine at the frozen commit ---
# The suite plan count catches deleted tests but not weakened ones, so probe
# the tree itself: HEAD must still be the pinned upstream commit and the
# working tree must be unmodified. A force-moved tag or an agent that edits
# /app/src (weakening a fixture so its own bypass passes) fails here.
PIN_SHA=1d7460c4f8a27be825c11b1c9d346d79db32c1e5
if [ "$(git -C /app/src rev-parse HEAD 2>/dev/null)" != "$PIN_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned upstream commit ($(git -C /app/src rev-parse HEAD 2>/dev/null || echo 'no git'))" >&2
  reward=0
elif [ -n "$(git -C /app/src status --porcelain 2>/dev/null)" ]; then
  echo "FAIL: /app/src working tree was modified from the upstream 3.4.15 state:" >&2
  git -C /app/src status --porcelain | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: /app/src pristine at $PIN_SHA"
fi

# --- 1. the project's own suite (the agent must keep it green, untouched) ---
echo "== running the project's own jsdom suite =="
if ( cd /app/src && node test/jsdom-node-runner > /tmp/suite.out 2>&1 ); then
  if grep -q '1..1227' /tmp/suite.out && ! grep -q 'not ok' /tmp/suite.out; then
    echo "ok: project suite green (1..1227)"
  else
    echo "FAIL: project suite did not report the full 1227 cases (a test was skipped/removed/broken)" >&2
    grep -i 'not ok' /tmp/suite.out | head -5 >&2 || true
    grep -o '1\.\.[0-9]*' /tmp/suite.out | tail -1 >&2 || true
    reward=0
  fi
else
  echo "FAIL: project suite failed to run" >&2
  grep -i 'not ok' /tmp/suite.out | head -10 >&2 || true
  reward=0
fi

# --- 2. the agent's bypass regression test ---
echo "== running /app/bypass-test.js =="
if node /app/bypass-test.js > /tmp/bypass.out 2>&1; then
  echo "ok: bypass-test passed"
else
  echo "FAIL: /app/bypass-test.js exited non-zero" >&2
  cat /tmp/bypass.out >&2
  reward=0
fi

# --- 3. hidden payloads through the hardened sanitizer ---
echo "== running hidden payloads through /app/sanitize.js =="
if node /tests/verify.js > /tmp/verify.out 2>&1; then
  echo "ok: hidden payloads sanitised"
else
  echo "FAIL: hidden payload checks" >&2
  cat /tmp/verify.out >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
