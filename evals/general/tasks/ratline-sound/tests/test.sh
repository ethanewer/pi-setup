#!/bin/bash
# Verifier for ratline-sound: an upstream-clone debugging task on spf13/cobra.
#
# The agent must, in the real checkout at /app/src, author its own failing
# reproduction at /app/repro/repro_test.go for a real upstream bug (a child
# flag that shadows a parent persistent flag disappears from the child's help
# and the parent's flag is shown under Global Flags; upstream issue #1776,
# fixed by 22b6179...) and then fix the behaviour. The verifier:
#   0. asserts provenance: pinned go toolchain sha256, golden regression-test
#      sha256, HEAD still the pinned parent commit, the upstream fix commit not
#      reachable, the reproduction deliverable present with at least one Test*
#      function, command.go modified, and nothing else in the tree changed;
#   1. runs the agent's OWN reproduction (extracted Test* function names,
#      -run filtered) against a fresh, untouched copy of the pre-fix tree
#      (`git archive HEAD` -- the agent cannot tamper with it) and requires it
#      to FAIL, proving it is a real reproduction;
#   2. runs the agent's own reproduction against the repaired tree and requires
#      it to PASS;
#   3. overlays the upstream regression test extracted from the fix commit at
#      build time (/opt/golden/command_test.go) onto the repaired tree and
#      requires the two upstream regression tests to PASS;
#   4. runs the project's own full existing suite against the repaired tree,
#      proving the fix broke nothing else;
#   5. runs three authored hidden cases (String-flag shadowing with exact
#      help-text equality; two children shadowing the parent's sole persistent
#      flag; a three-level tree where the grandchild shadows the grandparent's
#      Int flag) -- each must PASS on the repaired tree and FAIL on the pre-fix
#      tree;
#   6. re-checks provenance after the hidden-case runs.
#
# Reward is binary and written on every exit path (trap below). The go test
# suite MUST run as an unprivileged user: one upstream test
# (TestFailGenFishCompletionFile) opens a 0400 file and expects "permission
# denied", which root bypasses. When this script runs as root it drops
# privileges to the uid-1000 user `ubuntu` with setpriv (util-linux).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/repro/repro_test.go
PARENT_SHA=dbf85f6104904d539cabceebec234e817fa0df0c
FIX_SHA=22b617914c8890ba20db7ceafcdc2ef4ca4817d3
GOLDEN=/opt/golden/command_test.go
# sha256 of the fix commit's command_test.go (immutable upstream content);
# a modified /opt/golden would let the agent rewrite the answer.
GOLDEN_SHA256=90cf3883ace41ea71117c04fc70bcbffd1afae10b4366163e096516f187de79a
# The go toolchain binary is pinned and must be byte-identical to the one the
# image was built with. A shim or replacement at this path would make every
# test stage 'pass' without running the real suite, so the verifier re-hashes
# it (the tests dir is uploaded fresh at verify time, so the agent cannot
# rewrite this expectation).
GO_BIN=/opt/go/bin/go
GO_SHA256=97788e7e91584bda693b8dc669c58ba3346cfd50de241aecba27ddd68d8098ff
GOLDEN_NAMES='TestHelpCommandExecutedOnChildWithFlagThatShadowsParentFlag|TestChildFlagShadowsParentPersistentFlag'

echo "== diagnostics: uid=$(id -u) cpus=$(nproc) =="

# run `$GO_BIN test -v ARGS...` inside DIR as the unprivileged user ubuntu
go_cmd () {  # go_cmd DIR [go test args...]
  local dir="$1"; shift
  local q="cd $(printf '%q' "$dir") && $GO_BIN test -v"
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  if [ "$(id -u)" = 0 ]; then
    setpriv --reuid=1000 --regid=1000 --clear-groups \
      env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
          GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
      sh -c "$q"
  else
    ( cd "$dir" && go test -v "$@" )
  fi
}

# fresh pre-fix tree: extract HEAD (= the pinned parent commit) into DEST
make_pristine () {  # make_pristine DEST
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$SRC" archive HEAD | tar -x -C "$dest"
  chown -R 1000:1000 "$dest"
}

# extract the Test* function names from a test file, joined with '|'
repro_names () {  # repro_names FILE
  grep -oE '^func (Test[A-Za-z0-9_]+)' "$1" | awk '{print $2}' | sort -u | paste -sd'|' -
}

echo "========== 0. provenance =========="
if [ ! -f "$GO_BIN" ]; then
  echo "FAIL: $GO_BIN missing (the go toolchain was removed or replaced)" >&2; reward=0
elif [ "$(sha256sum "$GO_BIN" | cut -d' ' -f1)" != "$GO_SHA256" ]; then
  echo "FAIL: $GO_BIN does not match the pinned go1.24.0 sha256 (a shim cannot stand in for the real suite)" >&2; reward=0
else
  echo "ok: go toolchain at $GO_BIN matches the pinned sha256"
fi

if [ ! -f "$GOLDEN" ]; then
  echo "FAIL: $GOLDEN missing (the upstream regression test was not extracted at build time)" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: $GOLDEN no longer matches the upstream regression test sha256 (the answer was edited)" >&2; reward=0
else
  echo "ok: golden regression test matches the upstream sha256"
fi

if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is the pinned parent commit $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ ! -f "$REPRO" ]; then
  echo "FAIL: deliverable $REPRO missing (no reproduction was authored)" >&2; reward=0
else
  n=$(repro_names "$REPRO" | tr -d '|')
  if [ -z "$n" ]; then
    echo "FAIL: $REPRO contains no test function named Test* -- the verifier cannot run it" >&2; reward=0
  else
    echo "ok: $REPRO present"
  fi
fi

if [ -z "$(git -C "$SRC" diff HEAD -- command.go 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src has no fix (the project source is unchanged from the pinned commit)" >&2
  reward=0
else
  echo "ok: command.go differs from the pinned commit"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -vE '^.. command\.go$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only command.go may differ):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: no other tracked or untracked changes in the repository"
fi

echo "========== 1. agent's own reproduction on the PRE-FIX tree (must FAIL) =========="
names=$(repro_names "$REPRO")
if [ -n "$names" ]; then
  REPRO_FILTER=$names
  make_pristine /tmp/pristine-repro
  cp "$REPRO" /tmp/pristine-repro/repro_test.go
  if go_cmd /tmp/pristine-repro ./... -run "$REPRO_FILTER" > /tmp/repro-pristine.out 2>&1; then
    echo "FAIL: the reproduction PASSED against the untouched pre-fix tree -- it does not reproduce the bug" >&2
    reward=0
  else
    echo "ok: the reproduction fails on the pre-fix tree as required (rc != 0)"
  fi
fi

echo "========== 2. agent's own reproduction on the REPAIRED tree (must PASS) =========="
if [ -n "$names" ]; then
  cp "$REPRO" "$SRC/repro_test.go"
  if go_cmd "$SRC" ./... -run "$REPRO_FILTER" > /tmp/repro-fixed.out 2>&1; then
    echo "ok: the reproduction passes against the repaired tree"
  else
    echo "FAIL: the reproduction fails against the repaired tree" >&2
    tail -30 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

echo "========== 3. golden: the upstream regression test on the repaired tree =========="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  cp "$GOLDEN" "$SRC/command_test.go"
  if go_cmd "$SRC" ./... -run "$GOLDEN_NAMES" > /tmp/golden.out 2>&1; then
    echo "ok: both upstream regression tests pass"
  else
    echo "FAIL: upstream regression tests fail on the repaired tree" >&2
    tail -40 /tmp/golden.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

echo "========== 4. the project's own full existing suite =========="
if go_cmd "$SRC" ./... > /tmp/full.out 2>&1; then
  echo "ok: the full existing suite passes"
else
  echo "FAIL: the full existing suite fails" >&2
  tail -40 /tmp/full.out | sed 's/^/    /' >&2
  reward=0
fi

echo "========== 5. hidden cases (PASS on repaired tree, FAIL on pre-fix tree) =========="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")

  # 5a. hidden case must pass on the repaired tree
  copied=""
  for f in "$case"*.go; do
    [ -f "$f" ] || continue
    dst="$SRC/zzhidden_${name}_$(basename "$f")"
    if cp -p "$f" "$dst" 2>/dev/null; then copied="$copied $dst"; else
      echo "FAIL: cannot place hidden case $name into the tree" >&2; reward=0
    fi
  done
  out="/tmp/hidden-fixed-${name}.out"
  if go_cmd "$SRC" ./... -run TestHidden > "$out" 2>&1; then
    echo "ok: hidden case $name passes on the repaired tree"
  else
    echo "FAIL: hidden case $name fails on the repaired tree" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
  for d in $copied; do rm -f "$d"; done

  # 5b. the same hidden case must FAIL on the pre-fix tree (it really tests
  #     the bug, so passing the golden test alone does not cover it)
  make_pristine /tmp/pristine-hidden
  copied=""
  for f in "$case"*.go; do
    [ -f "$f" ] || continue
    dst="/tmp/pristine-hidden/zzhidden_${name}_$(basename "$f")"
    if cp -p "$f" "$dst" 2>/dev/null; then copied="$copied $dst"; fi
  done
  out="/tmp/hidden-pristine-${name}.out"
  if go_cmd /tmp/pristine-hidden ./... -run TestHidden > "$out" 2>&1; then
    echo "FAIL: hidden case $name passes on the untouched pre-fix tree -- it does not exercise the bug" >&2
    reward=0
  else
    echo "ok: hidden case $name fails on the pre-fix tree as expected"
  fi
  for d in $copied; do rm -f "$d"; done
  rm -rf /tmp/pristine-hidden
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi
rm -rf /tmp/pristine-repro

echo "========== 6. final provenance =========="
rm -f "$SRC/repro_test.go"
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: HEAD moved away from the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is still the pinned parent commit"
fi
if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit became reachable" >&2; reward=0
else
  echo "ok: the upstream fix commit remains unreachable"
fi
if [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: golden regression test was modified" >&2; reward=0
fi
post=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
extra=$(printf '%s\n' "$post" | grep -vE '^.. command\.go$' | grep -vE '^.. command_test\.go$' || true)
if [ -n "$extra" ]; then
  echo "FAIL: cleanup did not restore the tree:" >&2
  printf '%s\n' "$extra" | head -5 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: only command.go and the overlaid golden command_test.go differ from the pinned commit"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0