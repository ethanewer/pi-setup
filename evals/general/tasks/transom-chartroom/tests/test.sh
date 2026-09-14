#!/bin/bash
# Verifier for transom-chartroom: an upstream-clone debugging task on
# psf/requests.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the header name/value validity regexes accept a name or value that ends
# with a newline character, because they anchor with '$' (which in Python's
# re matches just before a trailing newline) instead of '\Z'. The agent's
# deliverable is a reproduction script /app/reproduce_header_newline_bug.py
# whose *contract* is: exit 0 iff every header pair ending in a newline
# raises requests.exceptions.InvalidHeader (and a plain valid header does
# not). The verifier:
#   0. asserts the deliverables exist and requests resolves into the tree;
#   1. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit object is not reachable, src/requests/_internal_utils.py
#      carries exactly the one source diff, and the pristine parent snapshot in
#      /opt/prefix is byte-identical to HEAD);
#   2. runs the agent's own reproduction against the pristine parent tree
#      (mounted on sys.path ahead of the installed copy) and requires it to
#      FAIL — proving the reproduction really captures the bug — and then
#      against the repaired tree and requires it to PASS;
#   3. runs the project's own regression test for this bug (extracted from
#      the fix commit at build time into /opt/golden) and requires all 13
#      parametrized cases to pass: 13 passed, 0 failed;
#   4. runs a slice of the project's existing unit suite and requires it to
#      stay green, proving the fix broke nothing else;
#   5. runs two authored hidden cases that exercise the same code path from
#      inputs the upstream test does not use (bytes header parts and
#      newline-after-whitespace value variants; and the full request path
#      against a local HTTP server), so passing the golden test alone is
#      insufficient.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/reproduce_header_newline_bug.py
PARENT_SHA=4443b1a847b190010c2972a658924b98b5db6360
FIX_SHA=bc7dd0fc4d56e808bcdd85ac2d797b3107c89259
GOLDEN=/opt/golden/test_requests.py
GOLDEN_SHA=c78ee6c624468dfb2d974a74a9e9e9192029516e6dcdbf5e69a1e90f6a389c30
IU=src/requests/_internal_utils.py

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. deliverables present, requests resolves into the tree ---------
echo "== deliverables =="
if [ ! -f "$REPRO" ]; then
  fail "deliverable $REPRO does not exist"
else
  echo "ok: $REPRO exists"
fi
if [ ! -d "$SRC/.git" ]; then
  fail "deliverable /app/src is not a git clone"
else
  echo "ok: /app/src is a git clone"
fi

req_file=$(python3 -c "import requests; print(requests.__file__)" 2>/dev/null || true)
case "$req_file" in
  /app/src/src/requests/__init__.py)
    echo "ok: import requests resolves to the tree: $req_file"
    ;;
  *)
    fail "import requests does not resolve into /app/src ($req_file)"
    ;;
esac

# ---------- 1. tree provenance -------------------------------------------------
echo "== tree provenance =="
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- "$IU" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: $IU differs from the pinned commit"
  porcelain=$(git -C "$SRC" status --porcelain --untracked-files=no 2>/dev/null || true)
  if [ "$porcelain" = " M $IU" ]; then
    echo "ok: the only tracked change is $IU"
  else
    fail "unexpected tracked working-tree changes (expected exactly  M $IU):"
    printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
  fi
fi

prefix_sha=$(sha256sum "/opt/prefix/$IU" 2>/dev/null | cut -d' ' -f1 || true)
head_sha=$(git -C "$SRC" show "HEAD:$IU" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
if [ -n "$prefix_sha" ] && [ "$prefix_sha" = "$head_sha" ]; then
  echo "ok: the pristine parent snapshot /opt/prefix matches HEAD"
else
  fail "the pristine parent snapshot /opt/prefix was altered or is missing"
fi

# ---------- 2. the agent's own reproduction, both directions -------------------
echo "== reproduction against the pristine parent tree (must FAIL) =="
cp "$SRC/$IU" /tmp/agent_iu.py
git -C "$SRC" checkout -- "$IU" >/dev/null 2>&1
PYTHONPATH=/opt/prefix/src python3 "$REPRO" > /tmp/repro-prefix.out 2>&1
rc_prefix=$?
cp /tmp/agent_iu.py "$SRC/$IU"
if [ "$rc_prefix" -ne 0 ]; then
  echo "ok: reproduction failed on the buggy tree (exit $rc_prefix), demonstrating the bug:"
  head -6 /tmp/repro-prefix.out | sed 's/^/    /'
else
  fail "the reproduction PASSED on the pristine (buggy) tree - it does not demonstrate the bug"
  head -6 /tmp/repro-prefix.out | sed 's/^/    /' >&2
fi

echo "== reproduction against the repaired tree (must PASS) =="
python3 "$REPRO" > /tmp/repro-fixed.out 2>&1
rc_fixed=$?
if [ "$rc_fixed" -eq 0 ]; then
  echo "ok: reproduction passed on the repaired tree: $(tail -1 /tmp/repro-fixed.out)"
else
  fail "the reproduction FAILED on the repaired tree (exit $rc_fixed):"
  head -10 /tmp/repro-fixed.out | sed 's/^/    /' >&2
fi

if [ "$reward" = 1 ]; then
  # ---------- 3. the project's own regression test from the fix commit ----------
  echo "== upstream regression test (test_header_no_return_chars) =="
  golden_sha=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1 || true)
  if [ "$golden_sha" != "$GOLDEN_SHA" ]; then
    fail "unexpected golden-test content (${golden_sha:-missing}); expected $GOLDEN_SHA"
  else
    cp "$GOLDEN" "$SRC/tests/_golden_header_test.py"
    ( cd "$SRC" && python3 -m pytest -q -p no:cacheprovider \
        tests/_golden_header_test.py -k header_no_return_chars ) \
      > /tmp/golden.out 2>&1
    rc_golden=$?
    rm -f "$SRC/tests/_golden_header_test.py"
    if [ "$rc_golden" -eq 0 ] && grep -Eq '13 passed' /tmp/golden.out \
       && ! grep -q '^FAILED' /tmp/golden.out; then
      echo "ok: golden regression test: $(grep -E '13 passed' /tmp/golden.out | tail -1)"
    else
      fail "the project's own regression test does not pass (exit $rc_golden)"
      tail -15 /tmp/golden.out | sed 's/^/    /' >&2
    fi
  fi

  # ---------- 4. project unit-suite slice (fix broke nothing else) --------------
  echo "== project unit-test slice (tests/test_utils.py test_hooks.py test_structures.py) =="
  ( cd "$SRC" && python3 -m pytest -q -p no:cacheprovider \
      tests/test_utils.py tests/test_hooks.py tests/test_structures.py ) \
    > /tmp/suite.out 2>&1
  rc_suite=$?
  if [ "$rc_suite" -eq 0 ] && grep -Eq ' passed' /tmp/suite.out \
     && ! grep -q '^FAILED' /tmp/suite.out; then
    echo "ok: unit-test slice green: $(grep -E ' passed' /tmp/suite.out | tail -1)"
  else
    fail "the project's unit-test slice is not green (exit $rc_suite)"
    tail -15 /tmp/suite.out | sed 's/^/    /' >&2
  fi

  # ---------- 5. authored hidden cases --------------------------------------------
  echo "== hidden cases =="
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    n_hidden=$((n_hidden + 1))
    cname=$(basename "$case")
    if [ -f "$case/run.py" ]; then
      ( cd /app && timeout 180 python3 "$case/run.py" ) > "/tmp/hidden-$cname.out" 2>&1
      rc_case=$?
      if [ "$rc_case" -eq 0 ] && grep -q "HIDDEN CASE .*: ok" "/tmp/hidden-$cname.out"; then
        echo "ok: hidden case $cname"
      else
        fail "hidden case $cname (exit $rc_case)"
        tail -15 "/tmp/hidden-$cname.out" | sed 's/^/    /' >&2
      fi
    else
      fail "hidden case $cname has no run.py"
    fi
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden cases were exercised"
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0