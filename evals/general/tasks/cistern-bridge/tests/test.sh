#!/bin/bash
# Verifier for cistern-bridge: DOMPurify case-preserving attribute removal.
#
# The agent must repair, in the real checkout at /app/src, the sanitizer's
# failure to remove event-handler / risky attributes whose stored names keep
# uppercase letters (created via the DOM API or an XML/XHTML parse), rebuild
# the committed dist artifact with the project's own build so the project's
# dist-based machinery exercises the fix, and leave the tree otherwise
# untouched. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no git
#      remotes exist, src/purify.ts and dist/purify.cjs.js are both modified,
#      no other tracked file changed and no new files appeared;
#   1. runs the agent's reproduction script (must be green after the fix);
#   2. runs the upstream regression tests for this defect, extracted at image
#      build time from the fix commit into /opt/golden/ (targeted module);
#   3. runs the project's own full jsdom test suite from /app/src, proving the
#      fix broke nothing else;
#   4. runs three authored hidden cases over inputs the upstream tests do not
#      use: other elements and handlers, several case-preserved attributes on
#      one node with safe-attribute preservation, and a reparse-sink scenario
#      that proves a surviving handler can no longer re-arm.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=8cc5ae1388587f7a08cc099ff2a5e985f85d77c5
FIX_SHA=083bb8aead7f6aba8cba30a9f954ade51f141c33
GOLDEN_RUNNER=/tests/golden-runner.js

fail () {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_node () {  # run_node LABEL OUT ...cmd
  label="$1"; out="$2"; shift 2
  if "$@" > "$out" 2>&1; then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
else
  head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
  if [ "$head" != "$PARENT_SHA" ]; then
    fail "HEAD is not the pinned parent commit (got ${head:-none})"
  else
    echo "ok: HEAD is $PARENT_SHA"
  fi

  if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
  else
    echo "ok: upstream fix commit is not present in the working clone"
  fi

  if [ -n "$(git -C "$SRC" remote 2>/dev/null || true)" ]; then
    fail "the working clone has git remotes (it must stay pristine)"
  else
    echo "ok: no git remotes"
  fi
fi

# 0b. The committed artifacts must be a faithful build of the source.
# Rebuild dist/ from src/ with the project's own build BEFORE grading. A
# hand-edited dist/purify.cjs.js that was never built from src/purify.ts is
# discarded here, so every functional gate below grades the SOURCE: a correct
# source fix rebuilds to fixed behavior, an unfixed source rebuilds to the
# buggy behavior and fails below. The porcelain checks then run against the
# tree as graded (the agent's source plus its own build).
echo "== rebuild committed artifacts from source =="
if ! (cd "$SRC" && npm run build > /tmp/rebuild.log 2>&1); then
  echo "FAIL: 'npm run build' failed; the graded tree cannot be produced" >&2
  tail -20 /tmp/rebuild.log | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: npm run build (artifacts regenerated from the source)"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ -z "$porcelain" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi
bad=$(printf '%s\n' "$porcelain" | grep -vE '^ M (src/purify\.ts|dist/.*)$' || true)
if [ -n "$bad" ]; then
  fail "unexpected working-tree changes (only src/purify.ts and committed dist/ artifacts may be modified):"
  printf '%s\n' "$bad" | head -12 | sed 's/^/    /' >&2
fi
printf '%s\n' "$porcelain" | grep -q '^ M src/purify\.ts$' \
  || fail "src/purify.ts is not modified (the source fix is the deliverable)"
printf '%s\n' "$porcelain" | grep -q '^ M dist/purify\.cjs\.js$' \
  || fail "dist/purify.cjs.js is not modified (the rebuilt artifact is required for the project's test machinery)"

# ---------- 1. the reproduction script ---------------------------------------
echo "== reproduction (/app/repro.js) =="
run_node "repro.js" /tmp/repro.out node /app/repro.js || true

# ---------- 2. golden: the upstream regression tests --------------------------
echo "== golden: upstream regression tests (from /opt/golden) =="
if [ ! -s /opt/golden/cistern-suite.js ]; then
  fail "golden module missing from image"
elif [ ! -s "$GOLDEN_RUNNER" ]; then
  fail "golden runner missing from /tests"
else
  run_node "golden cistern-suite" /tmp/golden.out node "$GOLDEN_RUNNER" || true
  if ! grep -q '^not ok' /tmp/golden.out 2>/dev/null; then
    n_ok=$(grep -c '^ok ' /tmp/golden.out 2>/dev/null || echo 0)
    echo "  golden: $n_ok upstream assertions passed"
  fi
fi

# ---------- 3. the project's own full jsdom suite -----------------------------
echo "== project's own jsdom suite =="
run_node "project jsdom suite" /tmp/project.out \
  bash -c "cd '$SRC' && node test/jsdom-node-runner.js --dot" || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  if [ -f "$case/check.js" ]; then
    out="/tmp/hidden-${name}.out"
    if node "$case/check.js" > "$out" 2>&1; then
      echo "ok: hidden case $name"
    else
      echo "FAIL: hidden case $name" >&2
      tail -40 "$out" | sed 's/^/    /' >&2
      reward=0
    fi
  else
    echo "FAIL: hidden case $name has no check.js" >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0