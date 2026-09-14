#!/bin/bash
# Verifier for poop-wheel: an upstream-clone debugging task on semgrep/semgrep.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# RuleMatch.is_blocking() consults the rule's general dev.semgrep.actions
# flag even for findings that went through validation, so a validator rule
# with a general "block" action blocks every validation state regardless of
# the per-state action (upstream issue #9943). The agent must also author
# /app/reproduce.py, a reproduction that detects the bug on an untouched
# tree and reports clean on the repaired tree. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the regression-test file is
#      byte-identical to the upstream regression test extracted at build
#      time, and the only tree changes are the source fix + that overlaid
#      test file; /opt/pristine is untouched);
#   1. runs the agent's own /app/reproduce.py against the pristine pre-fix
#      tree concept (/opt/pristine) and requires it to detect the bug, and
#      against the repaired tree and requires it to report clean;
#   2. runs the project's own unit tests: the 16 tests of the regression
#      file (including the 7 parametrized upstream cases) plus test_rule.py
#      must report 19 passed, with the parametrized validator-blocking
#      cases all passing;
#   3. runs three authored hidden-case drivers (validation states / action
#      maps / absent general action that the upstream parametrization does
#      not use) against the repaired tree.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=ae531156ca6f2f692827696723e35b786fb7fa92
FIX_SHA=c7d2925fbe7495bc9684f61be6212a438e438dd2
GOLDEN_SHA=f45c58e60aecc51d5c6d61011fdd91511fde7c3ba127492191174d3c54e30e1e
PARENT_RULE_SHA=a063b48e0c19c36753fb1d06134445f277120da459afcda656b8dd60b20d9990
PY=$(command -v python3 || echo python3)
GOLDEN=cli/tests/default/unit/test_rule_match.py
RULE_SRC=cli/src/semgrep/rule_match.py
PR=/opt/pristine

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
  fail "the upstream fix commit is reachable from the working clone"
else
  echo "ok: the upstream fix commit is not present in the working clone"
fi

if [ "$(git -C "$SRC" log --all --oneline 2>/dev/null | wc -l)" = "1" ]; then
  echo "ok: the working clone holds exactly one commit (nothing post-fix is readable)"
else
  fail "the working clone exposes more than the pinned commit (leaked post-fix content)"
fi

changed=$(git -C "$SRC" diff --name-only HEAD 2>/dev/null || true)
expected_changed="$RULE_SRC"$'\n'"$GOLDEN"
if [ "$changed" = "$expected_changed" ]; then
  echo "ok: tracked changes are exactly the source fix and the regression-test file"
else
  fail "unexpected tracked changes:"
  printf '%s\n' "$changed" | head -10 | sed 's/^/    /' >&2
fi

if [ -z "$(git -C "$SRC" diff HEAD -- "$RULE_SRC" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: $RULE_SRC differs from the pinned commit"
fi

# anti-hidden-change: the worktree source must differ from the HEAD blob even
# if the agent used assume-unchanged or other index tricks
head_rule=$(git -C "$SRC" show "HEAD:$RULE_SRC" 2>/dev/null | sha256sum | cut -d' ' -f1)
work_rule=$(sha256sum < "$SRC/$RULE_SRC" 2>/dev/null | cut -d' ' -f1)
if [ "$head_rule" != "$work_rule" ]; then
  echo "ok: worktree $RULE_SRC differs from its HEAD blob"
else
  fail "worktree $RULE_SRC is byte-identical to the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: $GOLDEN is byte-identical to the upstream regression test"
else
  fail "$GOLDEN was altered (${tree_golden:-missing})"
fi

untracked=$(git -C "$SRC" status --porcelain 2>/dev/null \
            | awk '$1=="??"{print $2}' \
            | grep -vE '__pycache__/|\.pytest_cache/|\.egg-info/|\.coverage|\.mypy_cache/' || true)
if [ -z "$untracked" ]; then
  echo "ok: no unexpected untracked files in the tree"
else
  fail "unexpected untracked files in the tree:"
  printf '%s\n' "$untracked" | head -10 | sed 's/^/    /' >&2
fi

# /opt/pristine must still be the untouched pre-fix tree concept
if [ "$(git -C "$PR" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ] \
   || [ "$(sha256sum < "$PR/$RULE_SRC" 2>/dev/null | cut -d' ' -f1)" != "$PARENT_RULE_SHA" ] \
   || [ "$(sha256sum < "$PR/$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  fail "/opt/pristine was modified (it must stay the untouched pre-fix tree)"
else
  echo "ok: /opt/pristine is the untouched pre-fix tree concept"
fi
if git -C "$PR" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the pristine clone"
fi
if [ "$(git -C "$PR" log --all --oneline 2>/dev/null | wc -l)" = "1" ]; then
  echo "ok: the pristine clone holds exactly one commit"
else
  fail "the pristine clone exposes more than the pinned commit"
fi

# ---------- 1. the agent's own reproduction ------------------------------------
echo "== the agent's reproduction (/app/reproduce.py) =="
if [ ! -f /app/reproduce.py ]; then
  fail "deliverable /app/reproduce.py is missing"
else
  echo "ok: /app/reproduce.py exists"
fi

if [ "$reward" = 1 ]; then
  echo "-- against the pristine (pre-fix) tree --"
  ( cd "$SRC" && PYTHONPATH="$PR/cli/src" "$PY" /app/reproduce.py > /tmp/repro-pristine.out 2>&1 )
  rc=$?
  echo "exit=$rc, last line: $(tail -1 /tmp/repro-pristine.out)"
  if [ "$rc" -eq 0 ] || ! grep -qE "^REPRO: [1-9][0-9]* failing" /tmp/repro-pristine.out; then
    fail "the reproduction does not detect the bug on a pristine tree"
    tail -8 /tmp/repro-pristine.out | sed 's/^/    /' >&2
  else
    echo "ok: the reproduction detects the bug on the pristine tree"
  fi
fi

if [ "$reward" = 1 ]; then
  echo "-- against the repaired tree --"
  ( cd "$SRC" && PYTHONPATH="$SRC/cli/src" "$PY" /app/reproduce.py > /tmp/repro-repaired.out 2>&1 )
  rc=$?
  echo "exit=$rc, last line: $(tail -1 /tmp/repro-repaired.out)"
  if [ "$rc" -eq 0 ] && grep -qE "^REPRO: 0 failing" /tmp/repro-repaired.out; then
    echo "ok: the reproduction reports clean on the repaired tree"
  else
    fail "the reproduction does not report clean on the repaired tree"
    tail -8 /tmp/repro-repaired.out | sed 's/^/    /' >&2
  fi
fi

# ---------- 2. the project's own tests -----------------------------------------
echo "== project's own unit tests =="
if [ "$reward" = 1 ]; then
  ( cd "$SRC" && PYTHONPATH="$SRC/cli/src" "$PY" -m pytest \
      cli/tests/default/unit/test_rule_match.py cli/tests/default/unit/test_rule.py \
      -q -p no:cacheprovider > /tmp/pytest-suite.out 2>&1 )
  echo "summary: $(tail -1 /tmp/pytest-suite.out)"
  if printf '%s' "$(tail -1 /tmp/pytest-suite.out)" | grep -qE '^19 passed in [0-9]'; then
    echo "ok: 19 passed"
  else
    fail "the project's own tests are not fully green (expected exactly '19 passed')"
    tail -15 /tmp/pytest-suite.out | sed 's/^/    /' >&2
  fi
fi

if [ "$reward" = 1 ]; then
  echo "== upstream regression cases (test_validator_rule_blocking) =="
  ( cd "$SRC" && PYTHONPATH="$SRC/cli/src" "$PY" -m pytest \
      cli/tests/default/unit/test_rule_match.py \
      -q -p no:cacheprovider -k test_validator_rule_blocking > /tmp/pytest-golden.out 2>&1 )
  echo "summary: $(tail -1 /tmp/pytest-golden.out)"
  if printf '%s' "$(tail -1 /tmp/pytest-golden.out)" | grep -qE '^7 passed(, [0-9]+ deselected)? in [0-9]'; then
    echo "ok: all 7 parametrized validator-blocking regression cases pass"
  else
    fail "the upstream regression cases did not all pass (expected exactly '7 passed')"
    tail -15 /tmp/pytest-golden.out | sed 's/^/    /' >&2
  fi
fi

# ---------- 3. hidden cases -----------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for f in /tests/hidden/*/*.py; do
  [ -f "$f" ] || continue
  n_hidden=$((n_hidden + 1))
  case_name=$(basename "$(dirname "$f")")
  if ! ( cd "$SRC" && PYTHONPATH="$SRC/cli/src" "$PY" "$f" > "/tmp/hidden-$case_name.out" 2>&1 ); then
    fail "hidden case $case_name"
    tail -8 "/tmp/hidden-$case_name.out" | sed 's/^/    /' >&2
  elif ! grep -qE "^REPRO: 0 failing" "/tmp/hidden-$case_name.out"; then
    fail "hidden case $case_name did not report clean"
    tail -8 "/tmp/hidden-$case_name.out" | sed 's/^/    /' >&2
  else
    echo "ok: hidden case $case_name: $(tail -1 "/tmp/hidden-$case_name.out")"
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised ($n_hidden)"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0