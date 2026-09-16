#!/bin/bash
# Verifier for garboard-yard: an upstream-clone debugging task on psutil.
#
# The agent receives a shallow clone of giampaolo/psutil at the buggy parent
# commit (real upstream issue #2793: process_iter() silently omits zombie
# processes) installed editable, and must (1) author a deterministic failing
# reproduction at /app/reproduce_zombie_skip.py BEFORE fixing anything, then
# (2) fix the library in /app/src so the reproduction passes and the project's
# own enumeration test class stays green. The verifier:
#
#   0. tree provenance: HEAD is still the pinned parent commit, the upstream
#      fix commit is not reachable from the clone, the only tracked-file
#      change is the library module the fix needs, and `import psutil`
#      resolves to /app/src;
#   1. the agent's own reproduction run in both directions: against the
#      pristine PRE-FIX tree (/opt/psutil-prefix, reached through the isolated
#      /opt/prefix-venv which cannot see the agent's editable install) it must
#      FAIL and report "BUG PRESENT"; against the repaired tree it must PASS
#      and report "FIXED";
#   2. the project's own regression test test_zombie_process_is_not_skipped
#      (extracted from the FIX commit at image build time, sha-asserted in
#      /opt/golden): must FAIL on the pre-fix tree and PASS on the repaired
#      tree;
#   3. authored hidden cases: two discriminating cases (multiple simultaneous
#      zombie-condition processes with cache-instance retention; a different
#      attrs tuple with ad_value and identity assertions) that must fail on
#      the pre-fix tree and pass on the repaired tree, plus a regression
#      guard (a genuinely vanished process must still be dropped) that must
#      pass on the repaired tree;
#   4. the project's own TestProcessIter class runs fully green.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# The agent phase shares this directory with the verifier. A stale or
# planted reward file must never survive into this run: if the verifier is
# killed before its final write (e.g. the agent hangs a command the verifier
# runs), the trap only writes when the file is ABSENT, so a planted "1"
# would otherwise stand. Truncating to 0 at startup makes every dead-early
# path score 0; the final echo at the bottom overwrites the true value.
echo 0 > /logs/verifier/reward.txt
reward=1

SRC=/app/src
PRE=/opt/psutil-prefix
PREFIX_PY=/opt/prefix-venv/bin/python
REPRO=/app/reproduce_zombie_skip.py
PARENT_SHA=1ae01d1210f73b411d38c0b7dc365727ae07608d
FIX_SHA=73a2bfb9152b20a85b4ea51d71b5d139c174aa02
# sha256 of tests/test_system.py at the fix commit
GOLDEN_SHA=92e9474a913fc0077e7faa477bec7222df95818eb06660737ccf006b82af86b4

fail() {
  echo "FAIL: $*" >&2
  reward=0
}

section() {
  echo
  echo "== $* =="
}

# ---------- 0. tree provenance -------------------------------------------------
section "tree provenance"

if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is the pinned parent $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone"
else
  echo "ok: the upstream fix commit is not present in /app/src/.git"
fi

if ! python3 -c "import psutil,sys; sys.exit(0 if psutil.__file__.startswith('/app/src/') else 1)" 2>/dev/null; then
  fail "system python does not import psutil from /app/src (deliverable bypassed)"
else
  echo "ok: psutil is imported from $SRC"
fi

if [ ! -f "$REPRO" ]; then
  fail "deliverable $REPRO is missing"
else
  echo "ok: reproduction deliverable $REPRO is present"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
touched=$(printf '%s\n' "$porcelain" | awk 'substr($0,2,1) ~ /[MD]/ {print substr($0,4)}' || true)
allowed="psutil/__init__.py"
extra=$(printf '%s\n' "$touched" | grep -vx "$allowed" || true)
if [ -n "$extra" ]; then
  fail "tracked files modified beyond $allowed:"
  printf '%s\n' "$extra" | sed 's/^/    /' >&2
else
  echo "ok: tracked changes are a subset of { $allowed }"
fi

# The instruction forbids adding files inside the repository; untracked files
# are invisible to the tracked-change check but a planted conftest.py would
# otherwise be loaded by the pytest runs below and could skip tests.
untracked=$(printf '%s\n' "$porcelain" | awk '/^\?\?/ {print substr($0,4)}' || true)
if [ -n "$untracked" ]; then
  fail "files were added inside the repository (only the minimal library change is allowed):"
  printf '%s\n' "$untracked" | sed 's/^/    /' >&2
else
  echo "ok: no files were added inside the repository"
fi

if [ -z "$(git -C "$SRC" diff -- psutil/__init__.py 2>/dev/null || true)" ]; then
  fail "$allowed is unchanged (no fix was implemented)"
else
  echo "ok: $allowed differs from the pinned commit"
fi
if ! grep -q 'def process_iter' "$SRC/psutil/__init__.py"; then
  fail "process_iter() is missing from $SRC/psutil/__init__.py"
fi

# ---------- 1. the agent's reproduction, both directions -------------------------
section "agent's reproduction: pre-fix tree must fail, repaired tree must pass"

if "$PREFIX_PY" "$REPRO" > /tmp/repro-pre.log 2>&1; then
  fail "the reproduction PASSED on the pristine pre-fix tree (it does not demonstrate the bug)"
  tail -5 /tmp/repro-pre.log | sed 's/^/    /' >&2
else
  echo "ok: reproduction fails on the pre-fix tree"
fi
if ! grep -q '^BUG PRESENT' /tmp/repro-pre.log 2>/dev/null; then
  fail "reproduction did not print 'BUG PRESENT' when run against the pre-fix tree"
  tail -5 /tmp/repro-pre.log | sed 's/^/    /' >&2
fi

if ! python3 "$REPRO" > /tmp/repro-fixed.log 2>&1; then
  fail "the reproduction FAILED on the repaired tree"
  tail -5 /tmp/repro-fixed.log | sed 's/^/    /' >&2
else
  echo "ok: reproduction passes on the repaired tree"
fi
if ! grep -q '^FIXED' /tmp/repro-fixed.log 2>/dev/null; then
  fail "reproduction did not print 'FIXED' when run against the repaired tree"
  tail -5 /tmp/repro-fixed.log | sed 's/^/    /' >&2
fi

# ---------- 2. the project's own regression test, both directions ----------------
section "upstream regression test (extracted from the fix commit at build time)"

# pre-fix direction: pytest run from the pristine tree; the venv python's
# sys.path[0] is the pre-fix tree, so psutil resolves there.
( cd "$PRE" && "$PREFIX_PY" -m pytest tests/test_system.py \
    -k test_zombie_process_is_not_skipped -q -p no:cacheprovider \
    > /tmp/golden-pre.log 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then
  fail "golden test PASSED on the pristine pre-fix tree (image state wrong or pre-fix env poisoned)"
  tail -5 /tmp/golden-pre.log | sed 's/^/    /' >&2
else
  echo "ok: golden test fails on the pristine pre-fix tree, as mined"
fi

# fixed direction: drop any untracked file the agent planted inside the
# repository (the agent is told not to add files; e.g. a conftest.py that
# would silently skip tests), then overlay the sha-checked upstream test file
# into the tree. `git clean -fd` removes untracked files only; ignored files
# (the compiled C extensions, build/, *.egg-info) are left alone.
git -C "$SRC" clean -fd --quiet
if ! cp /opt/golden/test_system.py "$SRC/tests/test_system.py"; then
  fail "could not overlay the golden test into $SRC/tests"
else
  got=$(sha256sum "$SRC/tests/test_system.py" | cut -d' ' -f1)
  if [ "$got" != "$GOLDEN_SHA" ]; then
    fail "overlaid golden test hash mismatch ($got vs $GOLDEN_SHA)"
  fi
fi

( cd "$SRC" && python3 -m pytest tests/test_system.py \
    -k test_zombie_process_is_not_skipped -q -p no:cacheprovider \
    > /tmp/golden-fixed.log 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "golden test FAILED against the repaired tree"
  tail -8 /tmp/golden-fixed.log | sed 's/^/    /' >&2
else
  echo "ok: golden test passes against the repaired tree"
fi

# ---------- 3. authored hidden cases ----------------------------------------------
section "hidden cases"
n_hidden=0
for check in /tests/hidden/*/check.sh; do
  [ -f "$check" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$(dirname "$check")")
  if bash "$check" > "/tmp/hc-$cname.log" 2>&1; then
    echo "ok: hidden case $cname"
  else
    fail "hidden case $cname"
    tail -8 "/tmp/hc-$cname.log" | sed 's/^/    /' >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

# ---------- 4. the project's own enumeration test class ----------------------------
section "project's own TestProcessIter class (must be fully green)"
( cd "$SRC" && python3 -m pytest tests/test_system.py -k TestProcessIter \
    -q -p no:cacheprovider > /tmp/classiter.log 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "the project's TestProcessIter class is not fully green"
  tail -15 /tmp/classiter.log | sed 's/^/    /' >&2
else
  passed=$(grep -Eo '[0-9]+ passed' /tmp/classiter.log | tail -1)
  if [ -z "$passed" ]; then
    fail "the TestProcessIter run selected or passed no tests (all skipped?)"
    tail -15 /tmp/classiter.log | sed 's/^/    /' >&2
  else
    echo "ok: TestProcessIter fully green ($passed)"
  fi
fi

echo
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0