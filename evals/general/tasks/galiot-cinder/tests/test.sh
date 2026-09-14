#!/bin/bash
# Verifier for galiot-cinder: an upstream-clone debugging task on
# falconry/falcon 4.0.0 at parent commit 7191be4d19592401f38a7b8e824e9669d34dad2b.
#
# The agent must (a) write its own failing reproduction at /app/reproduce_bug.py
# and (b) fix the RAW_URI defect in the checkout at /app/src. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, git status shows exactly the one
#      modified source file, the repair differs from the parent, and the
#      regression test extracted at build time to /opt/golden is byte-identical
#      to the pinned constant (tamper-proof);
#   1. runs the agent's reproduction against a pristine export of the parent
#      tree (git archive HEAD) in pure-Python mode: it must detect the defect
#      and exit nonzero — that is what proves the reproduction encodes the bug —
#      and then against the repaired /app/src tree: it must exit 0;
#   2. runs the project's own regression test (verbatim from the fix commit)
#      against the pristine tree, where it must FAIL, and against the repaired
#      tree, where it must PASS;
#   3. runs the whole project test module tests/test_testing.py on the repaired
#      tree: all 42 tests must pass (nothing else broke);
#   4. runs three authored hidden-case modules exercising the same code path
#      from inputs the upstream regression test does not use.
#
# Every run against a WORKING TREE (pristine and repaired alike) is executed
# with `python3 -S` and an explicit PYTHONPATH, so Python never processes
# site .pth files or sitecustomize: a "fix" hidden outside the checkout (a
# site-packages .pth, a user-site module, an edited sitecustomize) never runs,
# and the only code under test is the repository exactly as the agent left it.
# The two reproduction invocations are otherwise symmetric (same cwd, same
# flags, PYTHONPATH always set), so a script that passes by detecting which
# run it is in rather than by exercising falcon cannot distinguish them.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/reproduce_bug.py
PARENT_SHA=7191be4d19592401f38a7b8e824e9669d34dad2b
FIX_SHA=69cdcd6edd2ee33f4ac9f7793e1cc3c4f99da692
GOLDEN=/opt/golden/test_preserve_raw_uri.py
GOLDEN_SHA=154850aeee62e41efe6802cd8f7bab214a39d5b2b98c80e0c7b372d9b93213e8
PRISTINE=/tmp/pristine
PYSP=$(python3 -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || echo /usr/local/lib/python3.12/site-packages)
SITEOFF="-S"   # never process site .pth / sitecustomize: repo code only

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

if [ "$reward" = 1 ]; then
  echo "== 0. tree provenance =="
  if [ ! -d "$SRC/.git" ]; then
    fail "/app/src is not a git clone"
  elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
    fail "/app/src HEAD is not the pinned parent commit"
  else
    echo "ok: HEAD is $PARENT_SHA"
  fi

  if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
  else
    echo "ok: the upstream fix commit is not present in the clone"
  fi

  if git -C "$SRC" diff --quiet -- falcon/testing/helpers.py 2>/dev/null; then
    fail "falcon/testing/helpers.py is unchanged from the parent commit (no repair)"
  else
    echo "ok: falcon/testing/helpers.py differs from the pinned commit"
  fi

  porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
  expected=" M falcon/testing/helpers.py"
  if [ "$porcelain" = "$expected" ]; then
    echo "ok: working tree differs from the pinned commit in exactly one source file"
  else
    fail "unexpected working-tree state:"
    printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
  fi

  if [ ! -f "$REPRO" ]; then
    fail "reproduction deliverable /app/reproduce_bug.py is missing"
  else
    echo "ok: /app/reproduce_bug.py present"
  fi

  golden_sha=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
  if [ "$golden_sha" = "$GOLDEN_SHA" ]; then
    echo "ok: harness regression test is byte-identical to the pinned constant"
  else
    fail "harness regression test was altered (${golden_sha:-missing})"
  fi
fi

if [ "$reward" = 1 ]; then
  echo "== 1. agent's reproduction =="
  rm -rf "$PRISTINE" && mkdir -p "$PRISTINE"
  git -C "$SRC" archive HEAD | tar -x -C "$PRISTINE"

  # --- against a pristine export of the parent tree: must detect the defect
  ( cd /tmp && PYTHONPATH="$PRISTINE" python3 $SITEOFF "$REPRO" ) > /tmp/repro-pristine.log 2>&1
  rc=$?
  if [ "$rc" -ne 0 ] && grep -q "RAW_URI" /tmp/repro-pristine.log; then
    echo "ok: reproduction exits $rc on the pristine tree and reports RAW_URI"
  else
    fail "reproduction does not detect the defect on the pristine tree (rc=$rc)"
    tail -8 /tmp/repro-pristine.log 2>/dev/null | sed 's/^/    /' >&2 || true
  fi

  # --- against the repaired tree: must pass (symmetric invocation: same
  # --- flags, same cwd, PYTHONPATH always set; only falcon differs)
  ( cd /tmp && PYTHONPATH="$SRC" python3 $SITEOFF "$REPRO" ) > /tmp/repro-fixed.log 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok: reproduction exits 0 on the repaired tree"
    grep -E "RAW_URI|PATH_INFO" /tmp/repro-fixed.log | sed 's/^/    /'
  else
    fail "reproduction still reports the defect on the repaired tree (rc=$rc)"
    tail -8 /tmp/repro-fixed.log 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

if [ "$reward" = 1 ]; then
  echo "== 2. project's own regression test (from the fix commit) =="
  # --- must FAIL on the pristine tree
  ( cd /tmp && PYTHONPATH="$PRISTINE" python3 $SITEOFF - <<'PY'
ns = {}
exec(compile(open('/opt/golden/test_preserve_raw_uri.py').read(), 'golden.py', 'exec'), ns)
try:
    ns['test_create_environ_preserve_raw_uri']()
except AssertionError:
    print('golden regression test fails on the pristine tree as expected')
else:
    raise SystemExit('golden regression test PASSED on the pristine tree')
PY
  ) > /tmp/golden-pristine.log 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] && grep -q "fails on the pristine tree as expected" /tmp/golden-pristine.log; then
    echo "ok: golden regression test fails on the pristine tree"
  else
    fail "golden regression test behaves unexpectedly on the pristine tree (rc=$rc)"
    tail -8 /tmp/golden-pristine.log 2>/dev/null | sed 's/^/    /' >&2 || true
  fi

  # --- must PASS on the repaired tree (repo-only code: no site .pth)
  ( cd /tmp && PYTHONPATH="$SRC:$PYSP" python3 $SITEOFF -m pytest "$GOLDEN" -q -p no:cacheprovider ) > /tmp/golden-fixed.log 2>&1
  if grep -q "1 passed" /tmp/golden-fixed.log; then
    echo "ok: golden regression test passes on the repaired tree"
  else
    fail "golden regression test does not pass on the repaired tree"
    tail -12 /tmp/golden-fixed.log 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

if [ "$reward" = 1 ]; then
  echo "== 3. project's own suite: tests/test_testing.py =="
  ( cd "$SRC" && PYTHONPATH="$SRC:$PYSP" python3 $SITEOFF -m pytest tests/test_testing.py -q -p no:cacheprovider ) > /tmp/suite.log 2>&1
  if grep -q "42 passed" /tmp/suite.log; then
    echo "ok: tests/test_testing.py: 42 passed"
  else
    fail "tests/test_testing.py is not fully green"
    tail -12 /tmp/suite.log 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

if [ "$reward" = 1 ]; then
  echo "== 4. authored hidden cases =="
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    cname=$(basename "$case")
    for f in "$case"test_*.py; do
      [ -f "$f" ] || continue
      n_hidden=$((n_hidden + 1))
      if ( cd "$SRC" && PYTHONPATH="$SRC:$PYSP" python3 $SITEOFF -m pytest "$f" -q -p no:cacheprovider ) > "/tmp/hidden-$cname.log" 2>&1 \
         && grep -q "passed" "/tmp/hidden-$cname.log"; then
        echo "ok: hidden case $cname: $(grep -E 'passed|failed' /tmp/hidden-$cname.log | tail -1)"
      else
        fail "hidden case $cname"
        tail -12 "/tmp/hidden-$cname.log" 2>/dev/null | sed 's/^/    /' >&2 || true
      fi
    done
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden cases were exercised"
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0