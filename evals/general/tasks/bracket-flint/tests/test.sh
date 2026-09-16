#!/bin/bash
# Verifier for bracket-flint: an upstream-clone debugging task on pytest-dev/pytest.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# @pytest.mark.parametrize("arg,", [("a",), ("b",)]) does not unpack the
# one-element tuples (each invocation receives the whole tuple instead of its
# single element). The verifier:
#   0. asserts tree provenance (HEAD descends from the pinned parent commit,
#      the upstream fix commit is not in the object store, exactly one tracked
#      source file differs from the parent, no untracked files were added to
#      the clone, the working-tree structures.py is not the parent blob, and
#      the pytest that runs is the editable checkout at /app/src/src);
#   1. runs the shipped probe so the fixed behaviour is demonstrated;
#   2. runs the project's own parametrize test module from the parent-era tree
#      (the fix must not have broken anything already passing);
#   3. runs the project's own regression tests for this bug, extracted at image
#      build time from the fix commit into /opt/golden/ (content hash-pinned
#      so a tampered golden file cannot buy a pass);
#   4. runs authored hidden cases over inputs the upstream test does not use.
#
# Every pytest invocation is bound with --confcutdir=/app/src so that no
# conftest.py/config outside the clone (e.g. one dropped at / or /app) can be
# loaded to fake the fix, and the hidden cases live under a read-only /tests
# mount on a conftest chain the clone never reaches.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=dde81b1948d1592b0156c2fdb79522ade6b4b857
FIX_SHA=3fc824a62cd5f724ff2ae9a3aff721cee7cb4cbf
GOLDEN=/opt/golden/metafunc.py
# sha256 of the fix-era testing/python/metafunc.py extracted by the Dockerfile
# from `git show 3fc824a6:testing/python/metafunc.py`.
GOLDEN_SHA256=0aa1e4a4fd978a9d6d1849295c34459dc9ba0c868eaa23c690d95a7c54d7e2a3
PROBE=/app/test_parametrize_comma.py
META="$SRC/testing/python/metafunc.py"

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest --confcutdir="$SRC" "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
  echo "FAIL: /app/src is not a git checkout" >&2; reward=0
else
  head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
  if [ -z "$head" ]; then
    echo "FAIL: cannot read HEAD of /app/src" >&2; reward=0
  elif [ "$head" != "$PARENT_SHA" ] && ! git -C "$SRC" merge-base --is-ancestor "$PARENT_SHA" "$head" 2>/dev/null; then
    echo "FAIL: HEAD does not descend from the pinned parent commit" >&2
    echo "    HEAD=$head parent=$PARENT_SHA" >&2
    reward=0
  else
    echo "ok: HEAD ($head) is the parent commit or its direct descendant"
  fi
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

# The import under test MUST be the editable checkout, not a package the agent
# could have installed over site-packages to fake the fix.
pyfile=$(cd / && python3 -c "import pytest; print(pytest.__file__)" 2>/dev/null || true)
case "$pyfile" in
  /app/src/src/*) echo "ok: imported pytest is the editable checkout ($pyfile)" ;;
  *)
    echo "FAIL: imported pytest is not the editable checkout at /app/src/src" >&2
    echo "    pytest.__file__=$pyfile" >&2
    reward=0
    ;;
esac

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^[ M][M ] src/_pytest/mark/structures.py$' | sed '/^$/d' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes. Only src/_pytest/mark/structures.py may be modified; untracked files (conftest.py, pytest.ini, ...) are rejected because they can fake the fix:" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi

changed=$(git -C "$SRC" diff "$PARENT_SHA" --name-only 2>/dev/null || true)
nonmin=$(printf '%s\n' "$changed" | grep -v '^src/_pytest/mark/structures.py$' | grep -v '^$' || true)
if [ -n "$nonmin" ]; then
  echo "FAIL: tracked files other than src/_pytest/mark/structures.py differ from the parent commit:" >&2
  printf '%s\n' "$nonmin" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(printf '%s\n' "$changed" | grep -v '^$' || true)" ]; then
  echo "FAIL: nothing differs from the parent commit (no fix was implemented)" >&2
  reward=0
fi

# The working-tree file itself must differ from the parent blob: this reads
# the file directly and is immune to index tricks (assume-unchanged etc.).
parent_blob=$(git -C "$SRC" rev-parse "$PARENT_SHA:src/_pytest/mark/structures.py" 2>/dev/null || true)
now_blob=$(git -C "$SRC" hash-object "$SRC/src/_pytest/mark/structures.py" 2>/dev/null || true)
if [ -z "$parent_blob" ] || [ -z "$now_blob" ] || [ "$now_blob" = "$parent_blob" ]; then
  echo "FAIL: src/_pytest/mark/structures.py is byte-identical to the parent blob" >&2
  reward=0
else
  echo "ok: structures.py differs from the parent blob"
fi

# ---------- 1. probe ----------------------------------------------------------
echo "== probe: comma-terminated argnames must unpack =="
run_pytest "probe /app/test_parametrize_comma.py" /tmp/probe.out "$PROBE" || true

# ---------- 2. the project's own existing parametrize test module -------------
echo "== the project's own existing parametrize test module =="
run_pytest "existing testing/python/metafunc.py" /tmp/own.out testing/python/metafunc.py \
  || true

# ---------- 3. golden: the upstream regression tests --------------------------
echo "== golden: upstream regression tests for this bug =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test file missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: golden test file does not match the pinned fix-era content (tampered?)" >&2
  reward=0
else
  echo "ok: golden test file matches the pinned fix-era content"
  # overlay the fix-era metafunc.py (parent-era file + the two new tests),
  # run exactly the two upstream regression tests, then restore the tree.
  cp "$META" /tmp/metafunc.py.orig
  cp "$GOLDEN" "$META"
  if ( cd "$SRC" && python3 -m pytest --confcutdir="$SRC" \
        "testing/python/metafunc.py::TestMetafunc::test_parametrize_single_arg_trailing_comma" \
        "testing/python/metafunc.py::TestMetafuncFunctional::test_parametrize_single_arg_trailing_comma_functional" \
        -q -p no:cacheprovider > /tmp/golden.out 2>&1 ); then
    echo "ok: golden regression tests"
  else
    echo "FAIL: golden regression tests" >&2
    tail -40 /tmp/golden.out | sed 's/^/    /' >&2
    reward=0
  fi
  cp /tmp/metafunc.py.orig "$META"
  rm -f /tmp/metafunc.py.orig
fi

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest --confcutdir="$SRC" "$case" -p no:cacheprovider -q > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0