#!/bin/bash
# Verifier for chainplate-boom: an upstream-clone debugging task on NLTK.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# chomsky_normal_form raises AttributeError ('str'/'int' object has no
# attribute 'label') whenever an internal node with more than two children
# has a plain terminal among those children, because the binarization step
# reads a label from every child.  The fix must carry the terminal's own
# string value into the intermediate node names so that both factor
# directions work, every result node has at most two children, and
# un_chomsky_normal_form recovers the exact original tree.
#
#   0. tree provenance: HEAD is still the pinned parent commit, the upstream
#      fix commit is not reachable from the working clone, exactly one
#      tracked file is modified (an unstaged edit, and no untracked files);
#   1. the project's own regression tests for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. a direct reproduction of the reported symptom through the public API;
#   3. the project's own existing tree-transform tests and doctest from the
#      tree, proving the fix broke nothing else;
#   4. authored hidden cases (terminal shapes, node arities, nesting depths
#      and horzMarkov/vertMarkov parameters the upstream tests do not use,
#      each with the exact round-trip contract) that the upstream tests do
#      not cover.
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
PARENT_SHA=52227d2afe764648864e59c851e991cf1d6cb77e
FIX_SHA=27b8ad6cd50a484590cb9409e5d2a891ab56e16c
GOLDEN=/opt/golden/test_treetransforms.py

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
# The working tree must contain EXACTLY one change: an unstaged edit of the
# transforms module.  Anything else fails provenance: other modified tracked
# files, staged changes, typechanges, and any untracked file anywhere in the
# tree.  Untracked files must be rejected because a wrapper (a steering
# conftest.py, a patched-in helper, ...) can supply the expected behaviour
# while the buggy code is left in place.
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M nltk/tree/transforms.py$' || true)
if [ -n "$porcelain" ] && [ -n "$bad" ]; then
  echo "FAIL: working tree must contain exactly one change, an unstaged edit of nltk/tree/transforms.py:" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
# git status --porcelain and git diff both honour the assume-unchanged /
# skip-worktree index bits: a second modified file hidden behind
# `git update-index --assume-unchanged` vanishes from both, so a real fix can
# live outside the one allowed file while the tree *looks* one-edit-clean.
# Detect those flags directly.
flagged=$(git -C "$SRC" ls-files -v 2>/dev/null | grep -E '^[a-z]|^S' || true)
if [ -n "$flagged" ]; then
  echo "FAIL: assume-unchanged/skip-worktree index flags on tracked files (changes hidden from git status/diff):" >&2
  printf '%s\n' "$flagged" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- nltk/tree/transforms.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression tests --------------------------
echo "== golden test (upstream regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden test_treetransforms.py" /tmp/golden.out "$GOLDEN" || true
fi

# ---------- 2. direct reproduction through the public API ---------------------
echo "== direct reproduction =="
if python3 - > /tmp/direct.out 2>&1 <<'PY'
# The behaviour under test must come from the delivered tree itself, not from
# a module shadow/wrapper planted elsewhere (system site-packages, a .pth
# hook, ...).  The editable install maps nltk to /app/src; anything else is
# an interception.
import nltk.tree.transforms as _transforms_mod
assert _transforms_mod.__file__.startswith("/app/src/"), _transforms_mod.__file__

from nltk.tree import Tree
from nltk.tree.transforms import chomsky_normal_form, un_chomsky_normal_form

# punctuation terminal among two subtrees: no crash + binary + round trip
for factor in ("right", "left"):
    tree = Tree.fromstring("(S (S 1) + (S 2))")
    expected = Tree.fromstring("(S (S 1) + (S 2))")
    chomsky_normal_form(tree, factor=factor)
    for subtree in tree.subtrees():
        assert len(subtree) <= 2, (factor, subtree)
    un_chomsky_normal_form(tree)
    assert tree == expected, (factor, tree)

# non-string terminal among three subtrees: no crash + binary
for factor in ("right", "left"):
    tree = Tree("S", [Tree("A", ["a"]), 7, Tree("B", ["b"]), Tree("C", ["c"])])
    chomsky_normal_form(tree, factor=factor)
    for subtree in tree.subtrees():
        assert len(subtree) <= 2, (factor, subtree)

print("ok: terminal siblings convert for both factors, stay binary, and round-trip")
PY
then
  echo "ok: direct reproduction"
else
  echo "FAIL: direct reproduction (expected no crash, at most 2 children per node, and an exact round trip)" >&2
  tail -20 /tmp/direct.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. the project's own existing tests -------------------------------
echo "== the project's own existing tests =="
run_pytest "existing nltk/test/unit/test_treetransforms.py" /tmp/own.out nltk/test/unit/test_treetransforms.py \
  || true
if ( cd "$SRC" && python3 -m doctest nltk/test/treetransforms.doctest ) > /tmp/own-doctest.out 2>&1; then
  echo "ok: the project's treetransforms doctest"
else
  echo "FAIL: the project's treetransforms doctest" >&2
  tail -30 /tmp/own-doctest.out | sed 's/^/    /' >&2
  reward=0
fi

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