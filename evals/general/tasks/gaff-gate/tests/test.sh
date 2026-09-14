#!/bin/bash
# gaff-gate verifier
#
# Stages (binary reward 1 only if every stage passes):
#   0. integrity: /app/src is a git repo pinned to the parent commit, the fix
#      commit object is unreachable in it, the extracted golden tests are
#      byte-intact (hash-pinned), the deliverable /app/reproduce.js exists, and
#      /app/src/lib/response.js is not a byte-identical copy of the upstream
#      fix (which would mean the agent fetched/imported the answer instead of
#      repairing the tree itself).
#   1. the AGENT's own reproduction must FAIL on a pristine copy of the
#      pre-fix tree (restored from git HEAD, so it is exactly the un-repaired
#      state the agent started from).
#   2. the AGENT's own reproduction must PASS on the repaired tree.
#   3. the upstream golden regression tests (fix-commit test/res.status.js and
#      test/res.sendStatus.js, extracted into /opt/golden at build time) must
#      PASS on the repaired tree.
#   4. the same golden tests must FAIL on the pristine tree — proving this
#      image really reproduces the defect (dependencies pinned here differ
#      from the mining container, so this is re-confirmed per task image).
#   5. four of the project's own pre-existing test files, restored from git
#      HEAD (so an agent that deletes or weakens them gains nothing), must
#      stay green on the repaired tree.
#   6. authored hidden cases for the status-code contract, driven through the
#      project's own machinery in /app/src, must pass.
#
# Every failure path prints a readable message and ends the stage with the
# reward still binary: the trap writes a scorable 0 if this script exits
# without writing the reward, and every explicit path writes 0 or 1.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

reward=1

PARENT_SHA=ee40a881f5d8cb4ce71bc45262fde8e4b7640d05
FIX_SHA=723b5451bbcbab69bc8ded50ccd6545a79b8fe64

# sha256 of the FIX-commit files, computed at authoring time from the same
# commits the image pins. An agent that edits /opt/golden (or the upstream
# fix, copied byte-for-byte) trips these.
GOLDEN_STATUS_SHA=2fe6137bcb25077ff88436c9286fc5d42d1a94951fdcd50e62919b2f13785c8f
GOLDEN_SENDSTATUS_SHA=94f1c9739f66160f27e3616c61532b251c038a64cf6658a851c0bc072201561d
UPSTREAM_FIXED_LIB_SHA=29a505fec2858f9a8ce3423f883979791318cb664963672c43c71852d77c2fd5

cd /app/src || { echo "FAIL: /app/src missing" >&2; reward=0; }

fail() { echo "  FAIL: $*" >&2; reward=0; }
ok()   { echo "  ok: $*"; }

# ---------------------------------------------------------------------------
# stage 0 — integrity
# ---------------------------------------------------------------------------
echo "== stage 0: tree integrity =="

if [ "$(git rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "HEAD is not the pinned upstream parent commit ($(git rev-parse HEAD 2>/dev/null || echo 'not a git repo')); the tree was re-pinned or committed"
else
  ok "HEAD pinned to $PARENT_SHA"
fi

if git cat-file -e "$FIX_SHA^{commit}" 2>/dev/null; then
  fail "the upstream fix commit object is reachable in /app/src — the answer was fetched into the working repository"
else
  ok "fix commit $FIX_SHA unreachable in /app/src"
fi

for gf in /opt/golden/res.status.js /opt/golden/res.sendStatus.js; do
  [ -f "$gf" ] || fail "golden file $gf missing from image"
done
if [ "$(sha256sum /opt/golden/res.status.js 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_STATUS_SHA" ]; then
  fail "/opt/golden/res.status.js was modified (hash mismatch)"
else
  ok "golden res.status.js intact"
fi
if [ "$(sha256sum /opt/golden/res.sendStatus.js 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SENDSTATUS_SHA" ]; then
  fail "/opt/golden/res.sendStatus.js was modified (hash mismatch)"
else
  ok "golden res.sendStatus.js intact"
fi

if [ ! -f /app/reproduce.js ]; then
  fail "deliverable /app/reproduce.js missing"
else
  ok "deliverable /app/reproduce.js present"
fi

if [ ! -f lib/response.js ]; then
  fail "lib/response.js missing from the tree"
else
  LIB_SHA=$(sha256sum lib/response.js | cut -d' ' -f1)
  if [ "$LIB_SHA" = "$UPSTREAM_FIXED_LIB_SHA" ]; then
    fail "lib/response.js is byte-identical to the upstream fix — the answer was copied, not authored"
  else
    ok "lib/response.js is not a verbatim copy of the upstream fix"
  fi
fi

# save the agent's repaired lib for the swap-based stages below
cp lib/response.js /tmp/agent-lib.js

# ---------------------------------------------------------------------------
# stage 1 — the agent's reproduction must detect the defect on the pre-fix tree
# ---------------------------------------------------------------------------
echo "== stage 1: agent reproduction vs pristine (pre-fix) tree =="
git show HEAD:lib/response.js > /tmp/pristine-lib.js
cp /tmp/pristine-lib.js lib/response.js
if ( cd / && node /app/reproduce.js > /tmp/repro-pristine.out 2>&1 ); then
  fail "the agent's reproduction exited 0 on the pristine tree — it does not detect the defect"
  sed 's/^/    /' /tmp/repro-pristine.out >&2
else
  ok "agent reproduction failed on the pristine tree (exit $?)"
  sed 's/^/    /' /tmp/repro-pristine.out | head -8 >&2
fi

# ---------------------------------------------------------------------------
# stage 2 — the agent's reproduction must pass on the repaired tree
# ---------------------------------------------------------------------------
echo "== stage 2: agent reproduction vs repaired tree =="
cp /tmp/agent-lib.js lib/response.js
( cd / && node /app/reproduce.js > /tmp/repro-fixed.out 2>&1 )
repro_rc=$?
if [ "$repro_rc" -eq 0 ]; then
  ok "agent reproduction passed on the repaired tree"
elif [ "$repro_rc" -eq 2 ]; then
  fail "the agent's reproduction cannot load the tree (/app/src)"
else
  fail "the agent's reproduction exited non-zero ($repro_rc) on the repaired tree"
  sed 's/^/    /' /tmp/repro-fixed.out >&2
fi

# ---------------------------------------------------------------------------
# stage 3 — the upstream golden regression tests must pass on the repaired tree
# ---------------------------------------------------------------------------
echo "== stage 3: golden regression tests vs repaired tree =="
cp /opt/golden/res.status.js test/res.status.js
cp /opt/golden/res.sendStatus.js test/res.sendStatus.js
if ./node_modules/.bin/mocha --require test/support/env --exit test/res.status.js > /tmp/golden-status-fixed.out 2>&1; then
  ok "golden test/res.status.js passed on the repaired tree"
else
  fail "golden test/res.status.js failed on the repaired tree"
  grep -E 'passing|failing|✗|[0-9]+\)' /tmp/golden-status-fixed.out | head -12 >&2
fi
if ./node_modules/.bin/mocha --require test/support/env --exit test/res.sendStatus.js > /tmp/golden-sendstatus-fixed.out 2>&1; then
  ok "golden test/res.sendStatus.js passed on the repaired tree"
else
  fail "golden test/res.sendStatus.js failed on the repaired tree"
  grep -E 'passing|failing|✗|[0-9]+\)' /tmp/golden-sendstatus-fixed.out | head -12 >&2
fi

# ---------------------------------------------------------------------------
# stage 4 — the same golden tests must FAIL on the pristine tree, proving the
# defect really reproduces in this image (dependency set re-confirmation)
# ---------------------------------------------------------------------------
echo "== stage 4: golden tests vs pristine tree (must fail there) =="
cp /tmp/pristine-lib.js lib/response.js
golden_discriminates=1
if ./node_modules/.bin/mocha --require test/support/env --exit test/res.status.js > /tmp/golden-status-pristine.out 2>&1; then
  fail "golden test/res.status.js passed on the pristine tree — the defect does not reproduce in this image"
  golden_discriminates=0
else
  fails=$(grep -Eo '[0-9]+ failing' /tmp/golden-status-pristine.out | head -1)
  ok "golden test/res.status.js failed on the pristine tree ($fails)"
fi
if [ "$golden_discriminates" -eq 1 ] && ./node_modules/.bin/mocha --require test/support/env --exit test/res.sendStatus.js > /tmp/golden-sendstatus-pristine.out 2>&1; then
  fail "golden test/res.sendStatus.js passed on the pristine tree — the defect does not reproduce in this image"
else
  fails=$(grep -Eo '[0-9]+ failing' /tmp/golden-sendstatus-pristine.out | head -1)
  ok "golden test/res.sendStatus.js failed on the pristine tree ($fails)"
fi
cp /tmp/agent-lib.js lib/response.js   # restore the repaired tree for the remaining stages

# ---------------------------------------------------------------------------
# stage 5 — the project's own pre-existing tests (restored from git HEAD) stay
# green on the repaired tree; deletion or weakening of the on-disk copies gains
# nothing because the verifier restores them itself.
# ---------------------------------------------------------------------------
echo "== stage 5: project's own existing tests on the repaired tree =="
for f in res.sendStatus.js res.send.js res.json.js res.location.js; do
  git show HEAD:test/$f > test/$f
  if ./node_modules/.bin/mocha --require test/support/env --exit test/$f > /tmp/reg-$f.out 2>&1; then
    pass=$(grep -Eo '[0-9]+ passing' /tmp/reg-$f.out | head -1)
    ok "test/$f green ($pass)"
  else
    fail "test/$f failed on the repaired tree"
    grep -E 'passing|failing|✗|[0-9]+\)' /tmp/reg-$f.out | head -10 >&2
  fi
done

# ---------------------------------------------------------------------------
# stage 6 — authored hidden cases through the project's own machinery
# ---------------------------------------------------------------------------
echo "== stage 6: hidden status-code contract cases =="
if ( cd /app && node /tests/verify.js > /tmp/hidden.out 2>&1 ); then
  ok "hidden cases passed"
  tail -1 /tmp/hidden.out | sed 's/^/    /'
else
  fail "hidden cases failed"
  sed 's/^/    /' /tmp/hidden.out >&2
fi

# ---------------------------------------------------------------------------
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0