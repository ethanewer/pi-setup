#!/bin/bash
# Verifier for scupper-gulf: an upstream-clone debugging task on syncthing.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug
# (syncthing issue #10709): the protocol dispatcher treats any block request
# with byte count <= 0 as a protocol violation and tears the connection down,
# so a zero-count request -- which current Syncthing nodes legitimately send
# for the blocks of empty files -- makes a mixed-version transfer never
# complete. The fix is to reject only strictly negative sizes.
#
# The brief deliberately withholds the reproduction, so the agent must write
# its own failing regression test. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, the only
#      modified source is lib/protocol/protocol.go plus test files under
#      lib/protocol/ (go.sum drift from running the Go tool is allowed), and
#      the tree actually contains an agent-authored reproduction test (a Test*
#      function that is not in the parent's blobs);
#   1. runs the agent's own reproduction against the PRE-FIX tree (protocol.go
#      reverted to the parent blob; the reproduction must FAIL there) and then
#      against the repaired tree (it must PASS);
#   2. runs the project's own regression tests for this bug, extracted at
#      image build time from the fix commit into /opt/golden/ (the fix
#      commit's lib/protocol/protocol_test.go), and the ENTIRE protocol test
#      package with that file in place, proving the fix broke nothing else;
#   3. runs at least two authored hidden cases that the upstream test does not
#      cover (different request id/name, two consecutive zero-count requests,
#      a zero-count request followed by a normal one on the same connection).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=3ec73403c1fece449d4776a8d62b159440455d80
FIX_SHA=6be1ff84802810ebf6ab5a5169f865333607a8a5
GOLDEN=/opt/golden/protocol_test.go
# sha256 of lib/protocol/protocol_test.go as extracted from the fix commit at
# image build time (git show 6be1ff84...:lib/protocol/protocol_test.go).
# Re-checked here because the golden file lives in the image's writable
# layer: replacing it with a trivially-passing copy would fake the regression
# gate while leaving the bug in place.
GOLDEN_SHA256=d5706f8387aa8c15a678ed6721d1ebe254feeeea8f4f0bab8dae3a5ea6ad8840
AGENT_FIX=/tmp/agent-fix.go
AGENT_TEST=/tmp/agent-test.go

run_go () {  # run_go LABEL OUT ...args  (runs in $SRC with a 1-CPU cap)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && timeout 480 go test "$@" > "$out" 2>&1 ); then
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
bad=$(printf '%s\n' "$porcelain" \
        | grep -v '^ M lib/protocol/protocol.go$' \
        | grep -v '^ M lib/protocol/.*_test.go$' \
        | grep -v '^?? lib/protocol/.*_test.go$' \
        | grep -v '^ M go.sum$' \
        | grep -v '^?? go.sum$' \
        | grep -v '^$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only lib/protocol/protocol.go, test files under lib/protocol/, and go.sum may change):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi

if [ -z "$(git -C "$SRC" diff -- lib/protocol/protocol.go 2>/dev/null || true)" ]; then
  echo "FAIL: lib/protocol/protocol.go is unchanged (no fix was implemented)" >&2
  reward=0
fi

# The trial runs as root (harbor does not override the container user), so a
# hostile agent could replace the `go` binary with a wrapper that fakes every
# `go test` result. Verified during review: such a wrapper scored 1 with the
# live `if msg.Size <= 0 {` gate untouched. Every behavioural gate in this
# verifier goes through `go`, so they are backed here by a source-level
# assertion on the live request-size gate itself, checked directly on the
# file with grep: the semantic fix has an exact source shape (a live
# "msg.Size < 0" branch, no live "msg.Size <= 0" branch), and any tree that
# still carries a live "<= 0" branch has not implemented it no matter what
# the tree's own toolchain reports. The two-line shapes accepted are the two
# one-symbol minimal rewrites of the parent's gate ("< 0" and its negative
# equivalent "<= -1").
live_lt=$(grep -cE '^[[:space:]]*if msg\.Size (< 0|<= -1) \{' "$SRC/lib/protocol/protocol.go" || true)
live_le=$(grep -cE '^[[:space:]]*if msg\.Size <= 0 \{' "$SRC/lib/protocol/protocol.go" || true)
if [ "$live_le" -ne 0 ] || [ "$live_lt" -ne 1 ]; then
  echo "FAIL: protocol.go request-size gate does not have the fixed shape: expected exactly one live 'if msg.Size < 0 {' branch and no live 'if msg.Size <= 0 {' branch (found <0/<=-1: $live_lt, <=0: $live_le); the tests here cannot be trusted if the toolchain was tampered with, so the live gate itself is asserted" >&2
  reward=0
fi

# Find the agent-authored reproduction test(s): Test* functions present in the
# current tree's protocol test files but absent from the parent commit's blobs.
now_names=$(for f in "$SRC"/lib/protocol/*_test.go; do
  [ -f "$f" ] || continue
  sed -nE 's/^func (Test[A-Za-z0-9_]+)\(.*/\1/p' "$f" 2>/dev/null || true
 done | sort -u)
parent_names=$(git -C "$SRC" ls-tree -r --name-only HEAD lib/protocol 2>/dev/null \
  | grep '_test\.go$' \
  | while read -r f; do git -C "$SRC" show "HEAD:$f" 2>/dev/null; done \
  | sed -nE 's/^func (Test[A-Za-z0-9_]+)\(.*/\1/p' | sort -u)
added=$(comm -23 <(printf '%s\n' "$now_names") <(printf '%s\n' "$parent_names") | grep -v '^$')
if [ -z "$added" ]; then
  echo "FAIL: no agent-authored reproduction test found (all Test* functions match the parent blobs; write your own regression test)" >&2
  reward=0
else
  echo "ok: agent-authored test(s): $(printf '%s ' $added)"
fi
added_regex=$(printf '%s' "$added" | paste -sd'|' -)

# ---------- 1. the agent's own reproduction, pre-fix and post-fix ------------
echo "== agent reproduction on the PRE-FIX tree (must fail) =="
if [ -z "$added" ]; then
  echo "skipped (no reproduction test found)" >&2
else
  cp "$SRC/lib/protocol/protocol.go" "$AGENT_FIX"
  git -C "$SRC" show "HEAD:lib/protocol/protocol.go" > "$SRC/lib/protocol/protocol.go"
  if ( cd "$SRC" && timeout 480 go test ./lib/protocol/ -run "$added_regex" -v > /tmp/prefix.out 2>&1 ); then
    echo "FAIL: agent reproduction PASSED against the pre-fix tree; a reproduction that does not fail on the buggy code proves nothing" >&2
    tail -20 /tmp/prefix.out | sed 's/^/    /' >&2
    reward=0
  elif grep -q -- '--- FAIL' /tmp/prefix.out; then
    echo "ok: reproduction failed on the pre-fix tree as required"
  else
    echo "FAIL: reproduction did not fail with a test failure on the pre-fix tree" >&2
    tail -20 /tmp/prefix.out | sed 's/^/    /' >&2
    reward=0
  fi
  cp "$AGENT_FIX" "$SRC/lib/protocol/protocol.go"
fi

echo "== agent reproduction on the REPAIRED tree (must pass) =="
if [ -z "$added" ]; then
  echo "skipped" >&2
else
  run_go "agent reproduction post-fix" /tmp/postfix.out \
    ./lib/protocol/ -run "$added_regex" -v || true
fi

# ---------- 2. golden: the upstream regression tests -------------------------
echo "== golden tests (upstream regression tests for this bug) =="
cp "$SRC/lib/protocol/protocol_test.go" "$AGENT_TEST"
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test file missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/protocol_test.go does not match the upstream fix-commit extraction (was it replaced?)" >&2
  reward=0
else
  cp "$GOLDEN" "$SRC/lib/protocol/protocol_test.go"
  run_go "golden TestRequestZeroSize + TestRequestMaxSize" /tmp/golden.out \
    ./lib/protocol/ -run 'TestRequestZeroSize|TestRequestMaxSize' -v || true
  run_go "entire protocol test package (regression)" /tmp/full.out \
    ./lib/protocol/ -v || true
fi

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  hiddenfile=$(ls "$case"*_test.go 2>/dev/null | head -1)
  [ -n "$hiddenfile" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  testfunc=$(sed -nE 's/^func (Test[A-Za-z0-9_]+)\(.*/\1/p' "$hiddenfile" | head -1)
  [ -n "$testfunc" ] || continue
  cp "$GOLDEN" "$SRC/lib/protocol/protocol_test.go"
  cp "$hiddenfile" "$SRC/lib/protocol/zzhidden_${name}_test.go"
  run_go "hidden case $name ($testfunc)" "/tmp/hidden-${name}.out" \
    ./lib/protocol/ -run "$testfunc" -v || true
  rm -f "$SRC/lib/protocol/zzhidden_${name}_test.go"
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# Restore the agent's own test file: the delivered tree must be theirs.
[ -f "$AGENT_TEST" ] && cp "$AGENT_TEST" "$SRC/lib/protocol/protocol_test.go"

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0