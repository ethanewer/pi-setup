#!/bin/bash
# Verifier for cistern-anchor: an upstream-clone debugging task on spf13/cobra.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Cobra's command resolution drops the value of a flag when that value happens
# to equal a subcommand name (upstream issue #1781). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, the
#      overlaid regression-test file command_test.go is byte-identical to the
#      upstream regression test extracted at build time into /opt/golden/,
#      command.go holds a non-empty diff, and nothing else in the repository
#      changed);
#   1. runs the project's own full test suite against the repaired tree,
#      proving the fix broke nothing else;
#   2. runs the upstream regression test (TestFind) and requires it to pass;
#   3. runs two authored hidden-case files that exercise the same Find() code
#      path from argument layouts the upstream test does not use (a
#      flag/subcommand-value-collision family and a two-level command tree),
#      both of which fail at the parent commit;
#   4. re-checks the tree provenance after the hidden-case runs.
#
# Reward is binary and written on every exit path (trap below).
#
# The go test suite MUST run as an unprivileged user: one upstream test
# (TestFailGenFishCompletionFile) opens a 0400 file and expects "permission
# denied", which root bypasses. When this script runs as root it therefore
# drops privileges to the uid-1000 user `ubuntu` with setpriv (util-linux).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=cc7e235fc26cfd0b5ae36c960f399eea4badaa3e
FIX_SHA=6b0bd3076cfafd1c108264ed1e4aa0c0fe3f8537
GOLDEN=/opt/golden/command_test.go
# The go toolchain binary is pinned and must be byte-identical to the one the
# image was built with. A shim or replacement placed at this path would make
# every test stage 'pass' without running the real suite, so the verifier
# re-hashes it (the tests dir is uploaded fresh at verify time, so the agent
# cannot rewrite this expectation).
GO_BIN=/opt/go/bin/go
GO_SHA256=97788e7e91584bda693b8dc669c58ba3346cfd50de241aecba27ddd68d8098ff

echo "== diagnostics: uid=$(id -u) cpus=$(nproc) =="

# run `$GO_BIN test -v ARGS...` inside /app/src as the unprivileged user ubuntu
go_cmd () {  # go_cmd [go test args...]
  local q="cd '$SRC' && $GO_BIN test -v"
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  if [ "$(id -u)" = 0 ]; then
    setpriv --reuid=1000 --regid=1000 --clear-groups \
      env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
          GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
      sh -c "$q"
  else
    ( cd "$SRC" && go test -v "$@" )
  fi
}

run_go_test () {  # run_go_test LABEL OUT [extra go args...]
  label="$1"; out="$2"; shift 2
  if go_cmd "$@" > "$out" 2>&1; then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. toolchain provenance ------------------------------------------
echo "== toolchain provenance =="
if [ ! -f "$GO_BIN" ]; then
  echo "FAIL: $GO_BIN missing (the go toolchain was removed or replaced)" >&2; reward=0
elif [ "$(sha256sum "$GO_BIN" | cut -d' ' -f1)" != "$GO_SHA256" ]; then
  echo "FAIL: $GO_BIN does not match the pinned go1.24.0 sha256 (a shim cannot stand in for the real suite)" >&2; reward=0
else
  echo "ok: go toolchain at $GO_BIN matches the pinned sha256"
fi

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
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

if [ -z "$(git -C "$SRC" diff HEAD -- command.go 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src has no fix (command.go is unchanged from the pinned commit)" >&2
  reward=0
else
  echo "ok: command.go differs from the pinned commit"
fi

if cmp -s "$SRC/command_test.go" "$GOLDEN" 2>/dev/null; then
  echo "ok: command_test.go is byte-identical to the upstream regression test"
else
  echo "FAIL: command_test.go no longer matches the upstream regression test (it must not be edited)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" |
      grep -vE '^.. command\.go$' |
      grep -vE '^.. command_test\.go$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only command.go and the overlaid command_test.go may differ):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: no other tracked or untracked changes in the repository"
fi

# ---------- 1. the project's own full existing suite -------------------------
echo "== the project's own full test suite =="
run_go_test "full suite" /tmp/full.out ./... || true

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test TestFind) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_go_test "golden TestFind" /tmp/golden.out ./... -run TestFind || true
fi

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
    dst="$SRC/zzhidden_${name}_$(basename "$f")"
    if cp -p "$f" "$dst" 2>/dev/null; then
      copied="$copied $dst"
    else
      echo "FAIL: cannot place hidden case $name into the tree" >&2
      reward=0
    fi
  done
  out="/tmp/hidden-${name}.out"
  if go_cmd ./... -run TestHidden > "$out" 2>&1; then
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

# ---------- 4. tree is clean again after the hidden-case runs -----------------
post=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
extra=$(printf '%s\n' "$post" |
        grep -vE '^.. command\.go$' |
        grep -vE '^.. command_test\.go$' || true)
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