#!/bin/bash
# Verifier for bracket-dune: an upstream-clone debugging task on prometheus.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the label matcher's public Prefix() API advertises a byte-for-byte prefix
# for case-insensitive regexes, so consumers pre-filtering label names by byte
# comparison drop labels the full regex would match. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the regression-test file the
#      image overlays into model/labels/ is byte-identical to the upstream
#      regression test, matcher.go holds a non-empty diff, and nothing else
#      in the repository changed);
#   1. runs the project's upstream regression test (TestPrefix) and requires
#      it to pass;
#   2. runs the project's own existing label-matching module suite end to end
#      (`go test ./model/labels`), proving the fix broke nothing else;
#   3. runs two authored hidden-case files: other inline case-insensitivity
#      flag placements through the regex path, and the downstream
#      prefix-pruning consumer path plus a no-regression guard that
#      case-sensitive prefixes are still advertised.
#
# Reward is binary and written on every exit path (trap below).
#
# NOTE: hidden-case files are temporarily copied into model/labels/ so the
# project's own test runner compiles and executes them, then removed; the
# provenance snapshot is taken before the copy and re-checked after cleanup.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=297523f69825b59e5e9afc121fd0263c4d0248e5
FIX_SHA=f075de91d03d59f3d5996f1662eb9f0d6de7c40e
GOLDEN=/opt/golden/matcher_test.go
GOLDEN_SHA=5103f31d0de8c8e4e3ac25c7f2378f17c70ac90e3895172ad1513735b1b7f9cd

run_go_test () {  # run_go_test LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && go test -v "$@" > "$out" 2>&1 ); then
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
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- model/labels/matcher.go 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
else
  echo "ok: matcher.go differs from the pinned commit"
fi

# Semantic gate: the fix must actually exist in the source. The verifier runs
# inside the same container the agent worked in, so a PATH shim or a replaced
# /opt/go/bin/go could otherwise mask a failing test run while the tree still
# carries the bug. Require that the working tree's Prefix() body itself (a)
# differs from the buggy parent body and (b) implements the case-insensitive
# guard, i.e. suppresses the advertised byte-for-byte prefix exactly when
# m.re.caseInsensitivePrefix is set. The parent matcher.go contains no
# occurrence of the identifier, so this cannot pass on an unfixed tree.
pfx_fn=$(sed -n '/^func (m \*Matcher) Prefix() string {/,/^}/p' "$SRC/model/labels/matcher.go" 2>/dev/null || true)
if printf '%s\n' "$pfx_fn" | grep -q 'caseInsensitivePrefix'; then
  echo "ok: Prefix() implements the case-insensitive prefix guard (the fix is present in the source)"
else
  echo "FAIL: Prefix() does not implement the case-insensitive prefix guard; the byte-exact-prefix bug remains in the source" >&2
  reward=0
fi

tree_golden=$(sha256sum < "$SRC/model/labels/matcher_test.go" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: model/labels/matcher_test.go is byte-identical to the upstream regression test"
else
  echo "FAIL: model/labels/matcher_test.go was altered (${tree_golden:-missing})" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" |
      grep -v '^ M model/labels/matcher.go$' |
      grep -v '^ M model/labels/matcher_test.go$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only model/labels/matcher.go and the overlaid matcher_test.go may differ):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: no other tracked or untracked changes in the repository"
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_go_test "golden TestPrefix" /tmp/golden.out ./model/labels -run TestPrefix \
    || true
fi

# ---------- 2. the project's own existing label-matching suite ---------------
echo "== the project's own model/labels module suite =="
run_go_test "existing model/labels suite" /tmp/own.out ./model/labels \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  copied=""
  for f in "$case"*.go; do
    [ -f "$f" ] || continue
    dst="$SRC/model/labels/zzhidden_${name}_$(basename "$f")"
    if cp -p "$f" "$dst" 2>/dev/null; then
      copied="$copied $dst"
    else
      echo "FAIL: cannot place hidden case $name into the tree" >&2
      reward=0
    fi
  done
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && go test -v ./model/labels -run TestHidden > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
  for d in $copied; do rm -f "$d"; done
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 4. tree is clean again after the hidden-case runs ----------------
post=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
extra=$(printf '%s\n' "$post" |
        grep -v '^ M model/labels/matcher.go$' |
        grep -v '^ M model/labels/matcher_test.go$' || true)
if [ -n "$extra" ]; then
  echo "FAIL: hidden-case cleanup did not restore the tree:" >&2
  printf '%s\n' "$extra" | head -5 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: tree restored after hidden-case runs"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0