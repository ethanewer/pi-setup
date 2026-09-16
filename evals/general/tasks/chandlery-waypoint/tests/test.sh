#!/bin/bash
# Verifier for chandlery-waypoint: a real-upstream debugging task on flake8.
#
# Agent deliverables: a fixed checkout at /app/src and a self-written
# reproduction at /app/reproduce_unknown_homedir.py. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, only src/flake8/options/config.py
#      differs from the pinned revision, the grader-held golden regression test
#      (/opt/golden) and the pristine pre-fix reference (/opt/flake8-pristine)
#      are untouched, and the reproduction deliverable exists;
#   1. runs the agent's reproduction against a fresh copy of the PRISTINE
#      (still buggy) tree and requires a nonzero exit carrying a
#      FileNotFoundError, then against the repaired tree and requires exit 0.
#      The repaired tree is RECONSTRUCTED as the pristine tree plus the
#      agent's src/flake8/options/config.py (the only file the contract
#      allows to differ), so no import-time side effect anywhere else -- a
#      hidden sitecustomize hook, a stale .pyc, an edited __init__.py -- can
#      satisfy the behavioral gates; a fix that lives outside config.py
#      therefore cannot pass;
#   2. injects the project's own regression test for this bug (extracted from
#      the upstream fix commit at image build time) into a fresh copy of the
#      repaired tree and runs the whole tests/unit/test_options_config.py file
#      plus the rest of the project's unit suite (all but one pre-existing
#      Python-3.12 DeprecationWarning incompatibility) -- everything must pass;
#      the same golden file run against a pristine copy must fail exactly once,
#      proving the repair is what turns it green;
#   3. runs three authored hidden cases that exercise the same code path from
#      inputs the upstream regression test does not use (PermissionError from
#      os.stat of the home path; an existing home whose config must still be
#      discovered; a deep multi-component nonexistent home). All three must
#      pass on the repaired tree; the first and third must fail on the pristine
#      tree to prove they genuinely bite.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PRISTINE=/opt/flake8-pristine
GOLDEN=/opt/golden/test_options_config.py
REPRO=/app/reproduce_unknown_homedir.py

PARENT_SHA=446b18d35a5fa0be6b3531d30a0706fc82247313
FIX_SHA=8b51ee4ea54241f85df23f3dd20390b1563d4521
PARENT_CONFIG_SHA=15232151756a2a0b6fdb849946fad53c57dc74018d299a1412c2a01d9076a974
PARENT_TESTFILE_SHA=9630d2bcebcc6ad0da7ef26d355892cde3d04b5ddbe7e3ee339489fe1aa9bb9c
GOLDEN_TESTFILE_SHA=2844daa634b987f75cf18e79eeba5de53766b492cce81cb12db6dd17ad5a21ef

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
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

cfg_now=$(sha256sum < "$SRC/src/flake8/options/config.py" 2>/dev/null | cut -d' ' -f1)
if [ -n "$cfg_now" ] && [ "$cfg_now" != "$PARENT_CONFIG_SHA" ]; then
  echo "ok: /app/src/src/flake8/options/config.py differs from the pinned parent"
else
  fail "the config module is missing or unchanged from the pinned parent (no fix implemented)"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null \
              | grep -v '\.pytest_cache' | grep -v '__pycache__' || true)
# The change may be unstaged (" M"), staged ("M ") or both ("MM"); anything
# else -- extra files, deletions, renames, untracked files -- is a violation.
case "$porcelain" in
  " M src/flake8/options/config.py"|\
  "M  src/flake8/options/config.py"|\
  "MM src/flake8/options/config.py")
    echo "ok: only src/flake8/options/config.py differs from the pinned commit"
    ;;
  *)
    fail "unexpected working-tree changes:"
    printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
    ;;
esac

# git index flags: `git update-index --assume-unchanged/--skip-worktree` would
# hide tracked changes from the porcelain check above; the build leaves no
# flagged file, so any flag means the tree lied about its own state.
flagged=$(git -C "$SRC" ls-files -v 2>/dev/null | grep -E '^(h|S)' || true)
if [ -z "$flagged" ]; then
  echo "ok: no assume-unchanged/skip-worktree flags on tracked files"
else
  fail "assume-unchanged/skip-worktree flags present on tracked files:"
  printf '%s\n' "$flagged" | head -5 | sed 's/^/    /' >&2
fi

# .git/info/exclude is the only way a NEW (untracked) file can hide from the
# porcelain check; the build leaves exactly two patterns appended to the git
# template, so any other line means the agent concealed files from the grader.
excl_extra=$(grep -vE '^#|^[[:space:]]*$' "$SRC/.git/info/exclude" 2>/dev/null \
               | grep -Fvx '__pycache__/' | grep -Fvx '.pytest_cache/' || true)
if [ -z "$excl_extra" ]; then
  echo "ok: .git/info/exclude matches the build-time content"
else
  fail ".git/info/exclude was extended (concealed files would not be auditable):"
  printf '%s\n' "$excl_extra" | head -5 | sed 's/^/    /' >&2
fi

golden_shasum=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_shasum" = "$GOLDEN_TESTFILE_SHA" ]; then
  echo "ok: /opt/golden carries the untouched upstream regression test"
else
  fail "the grader-held golden regression test was altered or removed"
fi

if [ -d "$PRISTINE/.git" ] \
   && [ "$(git -C "$PRISTINE" rev-parse HEAD 2>/dev/null)" = "$PARENT_SHA" ] \
   && [ "$(sha256sum < "$PRISTINE/src/flake8/options/config.py" 2>/dev/null | cut -d' ' -f1)" = "$PARENT_CONFIG_SHA" ] \
   && [ "$(sha256sum < "$PRISTINE/tests/unit/test_options_config.py" 2>/dev/null | cut -d' ' -f1)" = "$PARENT_TESTFILE_SHA" ]; then
  echo "ok: the pristine pre-fix reference tree is intact"
else
  fail "the pristine pre-fix reference tree was altered or removed"
fi

if [ -f "$REPRO" ]; then
  echo "ok: deliverable /app/reproduce_unknown_homedir.py exists"
else
  fail "deliverable /app/reproduce_unknown_homedir.py is missing"
fi

# ---------- 1. the agent's reproduction: crash on the buggy tree, pass on the fixed tree ----
echo "== the agent's reproduction =="
if [ "$reward" = 1 ]; then
  rm -rf /tmp/pristine-check /tmp/verify-tree /tmp/hidden-check
  cp -a "$PRISTINE" /tmp/pristine-check
  # Reconstruct the repaired tree: pristine + the agent's config.py change.
  # Everything else from the agent's tree is deliberately not carried over, so
  # only a real change to the declared file can flip the behavioral gates.
  cp -a "$PRISTINE" /tmp/verify-tree
  cp "$SRC/src/flake8/options/config.py" /tmp/verify-tree/src/flake8/options/config.py
  mkdir -p /tmp/hidden-check

  out=$(HOME=/nonexistent-home-for-verifier PYTHONPATH=/tmp/pristine-check/src \
        python3 "$REPRO" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FileNotFoundError"; then
    echo "ok: reproduction fails on the buggy tree (rc=$rc, FileNotFoundError)"
  else
    fail "reproduction did not crash on the buggy tree (rc=$rc)"
    printf '%s\n' "$out" | tail -6 | sed 's/^/    /' >&2
  fi

  out=$(HOME=/nonexistent-home-for-verifier PYTHONPATH=/tmp/verify-tree/src \
        python3 "$REPRO" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok: reproduction passes on the repaired tree"
  else
    fail "reproduction failed on the repaired tree (rc=$rc)"
    printf '%s\n' "$out" | tail -6 | sed 's/^/    /' >&2
  fi
fi

# ---------- 2. golden regression test + the project's own suite on the repaired tree ----
echo "== the project's own regression test on the repaired tree =="
if [ "$reward" = 1 ]; then
  cp "$GOLDEN" /tmp/verify-tree/tests/unit/test_options_config.py
  ( cd /tmp/verify-tree \
      && PYTHONPATH=/tmp/verify-tree/src python3 -m pytest -p no:cacheprovider \
           tests/unit/test_options_config.py -q > /tmp/golden-repaired.log 2>&1 )
  if grep -qE "24 passed" /tmp/golden-repaired.log; then
    echo "ok: config test file green on the repaired tree (24 passed, incl. the regression test)"
  else
    fail "the project's config test file is not green on the repaired tree"
    tail -12 /tmp/golden-repaired.log | sed 's/^/    /' >&2
  fi

  ( cd /tmp/verify-tree \
      && PYTHONPATH=/tmp/verify-tree/src python3 -m pytest -p no:cacheprovider \
           "tests/unit/test_options_config.py::test_find_config_ignores_unknown_homedir" -q \
           > /tmp/golden-one.log 2>&1 )
  if grep -qE "1 passed" /tmp/golden-one.log; then
    echo "ok: test_find_config_ignores_unknown_homedir (the upstream regression) passes"
  else
    fail "the upstream regression test did not pass on the repaired tree"
    tail -10 /tmp/golden-one.log | sed 's/^/    /' >&2
  fi
fi

echo "== sanity: the same regression test must fail against a pristine copy =="
if [ "$reward" = 1 ]; then
  cp "$GOLDEN" /tmp/pristine-check/tests/unit/test_options_config.py
  ( cd /tmp/pristine-check \
      && PYTHONPATH=/tmp/pristine-check/src python3 -m pytest -p no:cacheprovider \
           tests/unit/test_options_config.py -q > /tmp/golden-pristine.log 2>&1 )
  if grep -qE "1 failed, 23 passed" /tmp/golden-pristine.log; then
    echo "ok: on the pristine tree the regression test fails exactly once (1 failed, 23 passed)"
  else
    fail "the pristine tree does not exhibit the bug (image drift?)"
    tail -10 /tmp/golden-pristine.log | sed 's/^/    /' >&2
  fi
fi

echo "== the project's own unit suite on the repaired tree =="
if [ "$reward" = 1 ]; then
  ( cd /tmp/verify-tree \
      && PYTHONPATH=/tmp/verify-tree/src python3 -m pytest -p no:cacheprovider tests/unit -q \
           -k "not test_undefined_local_code" > /tmp/unit-repaired.log 2>&1 )
  if grep -q "passed" /tmp/unit-repaired.log \
     && ! grep -qE "failed|error" /tmp/unit-repaired.log; then
    echo "ok: project unit suite green (all but the documented Python-3.12 environment incompatibility)"
  else
    fail "the project's unit suite has failures beyond the documented environment incompatibility"
    tail -15 /tmp/unit-repaired.log | sed 's/^/    /' >&2
  fi
fi

# ---------- 3. authored hidden cases ------------------------------------------
# Cases are copied to /tmp so the runs never depend on the /tests mount being
# writable, and the cache provider is disabled so pytest leaves no artifacts.
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  for f in "$case"*.py; do
    [ -f "$f" ] || continue
    cp "$f" "/tmp/hidden-check/${cname}.py"
    if [ "$reward" = 1 ]; then
      ( cd /tmp/verify-tree \
          && PYTHONPATH=/tmp/verify-tree/src python3 -m pytest -p no:cacheprovider \
               "/tmp/hidden-check/${cname}.py" -q > "/tmp/hidden-$cname.log" 2>&1 )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "ok: hidden case $cname passes on the repaired tree"
      else
        fail "hidden case $cname failed on the repaired tree"
        tail -10 "/tmp/hidden-$cname.log" | sed 's/^/    /' >&2
      fi
    fi
    case "$cname" in
      h1-*|h3-*)
        ( cd /tmp/pristine-check \
            && PYTHONPATH=/tmp/pristine-check/src python3 -m pytest -p no:cacheprovider \
                 "/tmp/hidden-check/${cname}.py" -q > "/tmp/pristine-$cname.log" 2>&1 )
        rc=$?
        if [ "$rc" -ne 0 ]; then
          echo "ok: hidden case $cname genuinely fails on the buggy tree"
        else
          fail "hidden case $cname does NOT fail on the buggy tree (it does not exercise the bug)"
        fi
        ;;
      h2-*)
        ( cd /tmp/pristine-check \
            && PYTHONPATH=/tmp/pristine-check/src python3 -m pytest -p no:cacheprovider \
                 "/tmp/hidden-check/${cname}.py" -q > "/tmp/pristine-$cname.log" 2>&1 )
        rc=$?
        if [ "$rc" -eq 0 ]; then
          echo "ok: hidden case $cname (existing-home guard) also passes on the buggy tree"
        else
          fail "hidden case $cname unexpectedly fails on the buggy tree"
          tail -10 "/tmp/pristine-$cname.log" | sed 's/^/    /' >&2
        fi
        ;;
    esac
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0