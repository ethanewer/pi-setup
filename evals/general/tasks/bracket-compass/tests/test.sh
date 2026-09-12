#!/bin/bash
# Verifier for bracket-compass: an upstream-clone debugging task on jinja2.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# required blocks containing statements crash the parser with an internal
# AttributeError instead of raising the intended TemplateSyntaxError
# ("Required blocks can only contain comments or whitespace").
#
#   0. tree provenance: HEAD is still the pinned parent commit, the upstream
#      fix commit is not reachable from the working clone, only the minimal
#      tracked source file is modified, and no new files appeared inside the
#      package;
#   1. the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. a direct reproduction of the reported symptom through the public API;
#   3. the project's own existing inheritance test file from the tree,
#      proving the fix broke nothing else;
#   4. authored hidden cases (statement kinds the upstream test does not use,
#      the exact error contract, and an inheritance/loader path) that the
#      upstream test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Disable user-site import injection: a usercustomize.py dropped in a writable
# user HOME must never be able to supply the expected behaviour on the
# verifier's own python processes.
export PYTHONNOUSERSITE=1
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=37f5b058ee4aaa01994ae4d378fc015bde484933
FIX_SHA=051df10c7b95b735ee53eeb1e9c8de1eb48ead14
GOLDEN=/opt/golden/test_inheritance.py
PTCFG="$SRC/setup.cfg"

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# The working tree must contain EXACTLY one change: an unstaged edit of
# src/jinja2/parser.py.  Anything else fails provenance: other modified
# tracked files, staged changes, typechanges, and any untracked file
# anywhere in the tree.  Untracked files must be rejected because a wrapper
# (a steering conftest.py, a patched-in helper, ...) can supply the expected
# behaviour while the buggy parser code is left in place.
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M src/jinja2/parser.py$' || true)
if [ -n "$porcelain" ] && [ -n "$bad" ]; then
  echo "FAIL: working tree must contain exactly one change, an unstaged edit of src/jinja2/parser.py:" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- src/jinja2/parser.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden test_invalid_required" /tmp/golden.out \
    "$GOLDEN::TestInheritance::test_invalid_required" || true
fi

# ---------- 2. direct reproduction through the public API ---------------------
echo "== direct reproduction =="
if python3 - > /tmp/direct.out 2>&1 <<'PY'
from jinja2 import Environment, TemplateSyntaxError

try:
    Environment().from_string(
        "{% block x required %}{% if true %}{% endif %}{% endblock %}"
    )
except TemplateSyntaxError as e:
    assert str(e) == "Required blocks can only contain comments or whitespace", str(e)
    print("ok: TemplateSyntaxError raised with the intended message")
else:
    raise SystemExit(
        "required block containing an if statement compiled without error"
    )
PY
then
  echo "ok: direct reproduction"
else
  echo "FAIL: direct reproduction (expected TemplateSyntaxError 'Required blocks can only contain comments or whitespace')" >&2
  tail -20 /tmp/direct.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. the project's own existing inheritance suite -------------------
echo "== the project's own existing inheritance tests =="
run_pytest "existing tests/test_inheritance.py" /tmp/own.out tests/test_inheritance.py \
  || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if run_pytest "hidden case $name" "$out" "$case"; then
    :
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0