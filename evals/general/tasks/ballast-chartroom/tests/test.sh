#!/bin/bash
# Verifier for ballast-chartroom: an upstream-clone debugging task on
# aquasecurity/trivy.
#
# Bug (upstream issue #10955): the conda environment-file parser replaces
# version operators with spaces and then indexes the first field of the
# split; a dependency entry made up only of operators (e.g. "=", "==") leaves
# an empty split and the parser panics with "index out of range [0] with
# length 0", aborting the whole scan. The agent must fix the real checkout at
# /app/src. The verifier:
#   0. asserts its own trust anchors. A root trial can substitute the toolchain
#      or the golden regression data; that attack was proven in review with a
#      stub /opt/go/bin/go that reported success for every "test" run while
#      the bug stayed in the source. The sha256 of the go toolchain binary and
#      of the two golden regression files are therefore hardcoded here and
#      checked before anything is executed. The Dockerfile asserts the same
#      values at image build and fails the build if they drift.
#   1. asserts tree provenance with BLOB-LEVEL content checks: every tracked
#      file is hashed from the working-tree bytes and compared to the parent
#      commit's own blob, so assume-unchanged/skip-worktree cannot hide a
#      dirty or deleted file. HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit is reachable,
#      every tracked file carries the parent's exact bytes except the conda
#      environment parser source (which must differ) and the regression test
#      (which must be the golden copy), and the only untracked file is the
#      golden fixture.
#   2. runs the project's own conda parser test scope (environment + meta
#      packages) from the repaired tree, the upstream regression case
#      included;
#   3. runs two authored hidden cases that exercise the same parser path from
#      operator-only inputs the upstream test does not use (runs of "=" beyond
#      length 2, entries interspersed between pinned packages, and whitespace
#      variants), asserting the exact parsed output.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=3dc5f8768b343a07694ba1cc09425f485d4c1b0f
FIX_SHA=f964fa2bb61e1b59088d2b35397ca8fd39045b00
GOLDEN=/opt/golden
ENVDIR=pkg/dependency/parser/conda/environment

# Trust anchors. sha256 of /opt/go/bin/go as extracted from the pinned
# actions/go-versions tarball 1.26.3-25533533231 and of the two golden files
# as extracted from the upstream fix commit f964fa2b. The Dockerfile asserts
# these same values at build time (it fails the build if they ever drift), so
# the verifier constants and the image cannot silently disagree.
GO_BIN_SHA=d68b7abbc40d0844f673f6cf06ae3cded225c50437c6454fa37ef178d079fe65
GOLDEN_PT_SHA=a4f841e7ad2e0d305c282a34867112a85d6e88e3e4306c7b78decbcb1ba69fb6
GOLDEN_OP_SHA=276da5f56f15a95dbed6a633f5d9a579bfed578f7e4f00cc6ba46cb4ef3e25f1

export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2

conda_scope_test () {  # conda_scope_test LABEL OUT
  label="$1"; out="$2"
  if ( cd "$SRC" && go test -v -short ./pkg/dependency/parser/conda/... > "$out" 2>&1 ); then
    if grep -qF "panic:" "$out"; then
      echo "FAIL: $label: run exited 0 but a runtime panic is present" >&2
      reward=0
      return 1
    fi
    if grep -q "FAIL" "$out"; then
      echo "FAIL: $label: run exited 0 but the log contains a FAIL line" >&2
      reward=0
      return 1
    fi
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -60 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. trust anchors ------------------------------------------------
echo "== trust anchors =="
anchors_ok=1
if [ "$(sha256sum /opt/go/bin/go 2>/dev/null | cut -d' ' -f1)" = "$GO_BIN_SHA" ]; then
  echo "ok: go toolchain binary carries the pinned sha256"
else
  echo "FAIL: /opt/go/bin/go is not the pinned toolchain binary (substituted or wrapped)" >&2
  anchors_ok=0
fi
if [ "$(sha256sum "$GOLDEN/parse_test.go" 2>/dev/null | cut -d' ' -f1)" = "$GOLDEN_PT_SHA" ] && \
   [ "$(sha256sum "$GOLDEN/operator-only-dep.yaml" 2>/dev/null | cut -d' ' -f1)" = "$GOLDEN_OP_SHA" ]; then
  echo "ok: golden regression test and fixture carry the pinned sha256"
else
  echo "FAIL: /opt/golden regression files are missing or do not carry the pinned sha256" >&2
  anchors_ok=0
fi
if [ "$anchors_ok" != 1 ]; then
  echo "REWARD=0"
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# ---------- 1. tree provenance (blob-level) --------------------------------
echo "== tree provenance =="
bad=0

if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$PARENT_SHA" ]; then
  echo "ok: HEAD is the pinned parent commit"
else
  echo "FAIL: HEAD is not the pinned parent commit $PARENT_SHA" >&2; bad=1
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  bad=1
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone has '$ncommits' reachable commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  bad=1
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

# The regression test and its fixture must be the golden bytes in the tree.
if [ "$(sha256sum "$SRC/$ENVDIR/parse_test.go" 2>/dev/null | cut -d' ' -f1)" = "$GOLDEN_PT_SHA" ]; then
  echo "ok: parse_test.go has the golden sha256"
else
  echo "FAIL: parse_test.go is missing or differs from the golden regression test" >&2
  bad=1
fi
if [ "$(sha256sum "$SRC/$ENVDIR/testdata/operator-only-dep.yaml" 2>/dev/null | cut -d' ' -f1)" = "$GOLDEN_OP_SHA" ]; then
  echo "ok: testdata/operator-only-dep.yaml has the golden sha256"
else
  echo "FAIL: testdata/operator-only-dep.yaml is missing or differs from the golden fixture" >&2
  bad=1
fi

# BLOB- AND FLAG-LEVEL provenance: worktree bytes are compared with the
# parent TREE using git's own normalization (git diff against the parent
# commit), so files with eol/attribute conversion in this repository do not
# false-positive, and every assume-unchanged/skip-worktree bit the agent may
# have set is cleared first so a dirty file cannot be hidden from the diff.
# parse.go must differ (the fix), parse_test.go is the golden copy (checked
# above), everything else must be byte-identical to the parent after
# normalization, and nothing may be staged.
flagged=0
while IFS= read -r line; do
  mode=$(printf '%s' "$line" | cut -c1)
  path=${line:2}
  case "$mode" in
    [a-z] | S)
      git -C "$SRC" update-index --no-assume-unchanged --no-skip-worktree -- "$path" 2>/dev/null || true
      flagged=1 ;;
  esac
done < <(git -C "$SRC" ls-files -v)
if [ "$flagged" = 1 ]; then
  echo "ok: cleared assume-unchanged/skip-worktree bits set in the working clone"
fi

dirty=$(git -C "$SRC" diff --name-only "$PARENT_SHA" -- 2>/dev/null || true)
saw_fix=0
out_of_scope=0
if [ -n "$dirty" ]; then
  while IFS= read -r f; do
    case "$f" in
      "$ENVDIR/parse.go") saw_fix=1 ;;
      "$ENVDIR/parse_test.go") : ;;  # golden overlay; sha256 asserted above
      *) echo "FAIL: out-of-scope modified or deleted tracked file: $f" >&2; out_of_scope=1 ;;
    esac
  done <<< "$dirty"
fi
if [ "$saw_fix" = 1 ]; then
  echo "ok: the conda environment parser source differs from the parent (fix implemented)"
else
  echo "FAIL: the conda environment parser source is unmodified (no fix implemented)" >&2
  bad=1
fi
[ "$out_of_scope" = 1 ] && bad=1

staged=$(git -C "$SRC" diff --cached --name-only "$PARENT_SHA" -- 2>/dev/null || true)
if [ -n "$staged" ]; then
  echo "FAIL: staged changes vs the parent: $staged (nothing may be staged)" >&2
  bad=1
else
  echo "ok: no staged changes"
fi

# Untracked files: exactly the golden fixture may exist; anything else fails.
extra=0
while IFS= read -r -d '' f; do
  if [ "$f" = "$ENVDIR/testdata/operator-only-dep.yaml" ]; then
    :  # golden fixture overlay; sha256 asserted above
  else
    echo "FAIL: unexpected untracked file inside the repository: $f" >&2
    extra=1
  fi
done < <(git -C "$SRC" ls-files --others --exclude-standard -z)
[ "$extra" = 0 ] || bad=1
[ "$bad" = 1 ] && reward=0

# ---------- 2. golden test + the project's own conda parser scope -----------
echo "== golden test + the project's own conda parser scope =="
cp "$GOLDEN/parse_test.go" "$SRC/$ENVDIR/parse_test.go"
cp "$GOLDEN/operator-only-dep.yaml" "$SRC/$ENVDIR/testdata/operator-only-dep.yaml"
conda_scope_test "project's own conda parser test scope (includes the upstream regression test)" /tmp/scope.out || true

# ---------- 3. hidden cases -------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  ok_copy=1
  mkdir -p "$SRC/$ENVDIR/testdata" || ok_copy=0
  cp "$case"/*_test.go "$SRC/$ENVDIR/" 2>/dev/null || ok_copy=0
  cp "$case"/testdata/*.yaml "$SRC/$ENVDIR/testdata/" 2>/dev/null || ok_copy=0
  if [ "$ok_copy" = 0 ]; then
    echo "FAIL: could not stage hidden case $name into the tree" >&2
    reward=0
    continue
  fi
  fname=$(ls "$case"/*_test.go 2>/dev/null | head -1)
  func=$(grep -oE 'func Test[A-Za-z0-9_]+' "$fname" 2>/dev/null | head -1 | awk '{print $2}')
  out="/tmp/hidden-$name.out"
  conda_scope_test "hidden case $name" "$out" || true
  if [ -n "$func" ] && ! grep -qF "=== RUN   $func" "$out"; then
    echo "FAIL: hidden case $name did not execute (no RUN line for $func in the test log)" >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0