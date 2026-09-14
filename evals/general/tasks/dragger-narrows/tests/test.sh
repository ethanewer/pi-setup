#!/bin/bash
# Verifier for dragger-narrows: whitespace-padded entries in .python-version
# / .python-versions are silently ignored by `uv python pin`.
#
# Strategy: (0) integrity anchors for the toolchain and the golden regression
# test as pinned at image build time; (1) provenance: HEAD still the pinned
# parent commit; (2) scope: the only acceptable tree change is the uncommitted
# fix to the version-file parser, byte-compared against the parent blob so
# assume-unchanged tricks fail; (3) the /app/repro.sh deliverable exists and
# is executable; (4) a forced offline rebuild of the agent's tree (candidate
# binary and parser artifacts deleted so nothing planted under git-ignored
# target/ can survive); (5) the project's own regression test for this bug,
# extracted from the fix commit at image build time into /opt/golden, planted
# and run -- it must pass on the repaired tree; (6) the agent's reproduction
# against the repaired binary; (7) authored hidden fixtures through the real
# binary on the repaired tree; (8) the pre-fix tree concept (the parent blob
# of the parser rebuilt into the binary) on which the reproduction and every
# hidden fixture must FAIL, proving the authored probes actually hit the bug;
# then restore the agent's repair. Only then reward 1.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
  echo "FAIL: $1"
  echo "FAIL: $1" >> "$LOG"
  echo 0 > /logs/verifier/reward.txt
  exit 0
}

export PATH=/opt/cargo/bin:$PATH
GIT=/usr/bin/git
CARGO=/opt/cargo/bin/cargo
PARENT=dbbc4c9a1e05ce37a94b3bf35fde29370429d312
FIX_SOURCE=crates/uv-python/src/version_files.rs
GOLDEN_TEST=crates/uv/tests/python/python_pin.rs

# probe: run `uv python pin` with the given binary in a scratch copy of a
# fixture directory (as cwd and HOME); leaves $out/$err/$rc as globals.
probe() { # $1 = uv binary, $2 = fixture dir
  local d
  d=$(mktemp -d /tmp/probe.XXXXXX) || return 1
  cp -a "$2/." "$d"/ 2>/dev/null
  ( cd "$d" && HOME="$d" XDG_CACHE_HOME="$d/.cache" "$1" python pin </dev/null >"$d/out" 2>"$d/err" )
  rc=$?
  out=$(cat "$d/out" 2>/dev/null)
  err=$(cat "$d/err" 2>/dev/null)
  rm -rf "$d"
  return 0
}

# 0) integrity anchors. The verifier executes the tree, the harness and the
#    golden test; an adversarial agent with write access to /opt (e.g. a root
#    trial) could otherwise swap /opt/cargo/bin/cargo for a stub that reports
#    success for every build, or replace the golden test with a vacuous one.
#    The pins recorded at image build time detect any substitution.
if ! ( cd / && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ); then
  fail "toolchain or golden integrity check failed (substituted binary or test)"
fi

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
  fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: the only acceptable change is the uncommitted fix to the
#    version-file parser, and its bytes must differ from the parent blob.
STATUS=$("$GIT" status --porcelain)
if [ -n "$STATUS" ]; then
  BAD=$(printf '%s\n' "$STATUS" | awk '{print $2}' | grep -vx "$FIX_SOURCE" || true)
  if [ -n "$BAD" ]; then
    fail "unexpected change in the tree: $(printf '%s\n' "$BAD" | tr '\n' ' ')"
  fi
else
  fail "the working tree is identical to the parent commit; no fix present"
fi
"$GIT" show "HEAD:$FIX_SOURCE" | sha256sum > /tmp/blob.sha
sha256sum < "$FIX_SOURCE" > /tmp/file.sha
if [ "$(cat /tmp/blob.sha)" = "$(cat /tmp/file.sha)" ]; then
  fail "the version-file parser is byte-identical to the parent commit; no fix present"
fi

# 3) the reproduction deliverable.
if [ ! -x /app/repro.sh ]; then
  fail "deliverable /app/repro.sh is missing or not executable"
fi

# 4) force a fresh offline build of the agent's tree.
rm -f target/debug/uv
"$CARGO" clean -p uv-python >> "$LOG" 2>&1 || fail "cargo clean -p uv-python failed"
"$CARGO" build -p uv >> "$LOG" 2>&1 || fail "cargo build -p uv failed on the repaired tree"
[ -x target/debug/uv ] || fail "no uv binary after the forced rebuild"

# 5) golden regression test from the fix commit, planted by the verifier.
mkdir -p "$(dirname "$GOLDEN_TEST")"
cp /opt/golden/python_pin.rs "$GOLDEN_TEST" || fail "could not plant the golden regression test"
rm -f target/debug/deps/python-* 2>/dev/null || true
GOUT=$("$CARGO" test -p uv --test python -- python_pin_with_comments_and_whitespace 2>&1); GRC=$?
printf '%s\n' "$GOUT" >> "$LOG"
if [ "$GRC" -ne 0 ]; then
  fail "golden regression test FAILED on the repaired tree (exit $GRC)"
fi
printf '%s\n' "$GOUT" | grep -q "python_pin_with_comments_and_whitespace \.\.\. ok" \
  || fail "golden regression test did not run green"
printf '%s\n' "$GOUT" | grep -q "1 passed" \
  || fail "golden regression test did not report exactly one passing test"

# 6) the agent's reproduction against the repaired binary.
RERR=$(mktemp)
OUT=$(UV_BIN=/app/src/target/debug/uv bash /app/repro.sh </dev/null 2>"$RERR"); RRC=$?
if [ "$RRC" -ne 0 ]; then
  fail "repro.sh exited $RRC on the repaired tree"
fi
if ! printf '%s\n' "$OUT" | grep -qx "3.12" || ! printf '%s\n' "$OUT" | grep -qx "3.10" \
   || [ "$(printf '%s\n' "$OUT" | grep -cE '.')" -ne 2 ]; then
  fail "repro.sh did not print exactly the pinned versions on the repaired tree (stdout=[$OUT])"
fi
if grep -q "Ignoring unsupported" "$RERR"; then
  fail "repro.sh still produced 'Ignoring unsupported Python request' warnings on the repaired tree"
fi
rm -f "$RERR"

# 7) hidden fixtures through the real binary on the repaired tree.
HIDDEN=0
for c in /tests/hidden/*; do
  [ -d "$c" ] || continue
  HIDDEN=$((HIDDEN + 1))
  name=$(basename "$c")
  exp=$(cat "$c/expected.txt")
  probe /app/src/target/debug/uv "$c"
  if [ "$rc" -ne 0 ] || [ "$out" != "$exp" ]; then
    fail "hidden case $name on the repaired tree: rc=$rc out=[$out] expected=[$exp]"
  fi
  if printf '%s' "$err" | grep -q "Ignoring unsupported"; then
    fail "hidden case $name on the repaired tree still ignores padded requests"
  fi
done
[ "$HIDDEN" -ge 2 ] || fail "fewer than two hidden cases found under /tests/hidden"

# 8) pre-fix tree concept: rebuild the parser's parent blob into the binary
#    and require the reproduction and every hidden fixture to FAIL.
cp "$FIX_SOURCE" /tmp/fixed-parser.rs
"$GIT" show "HEAD:$FIX_SOURCE" > "$FIX_SOURCE" || fail "could not restore the parent parser source"
"$CARGO" build -p uv >> "$LOG" 2>&1 || fail "pre-fix rebuild failed"
PERR=$(mktemp)
OUT=$(UV_BIN=/app/src/target/debug/uv bash /app/repro.sh </dev/null 2>"$PERR")
if printf '%s\n' "$OUT" | grep -qE '^3\.(12|10)$'; then
  fail "reproduction printed pins on the pre-fix tree (the bug did not reproduce)"
fi
grep -q "Ignoring unsupported" "$PERR" || fail "pre-fix reproduction did not emit the unsupported-request warning"
rm -f "$PERR"
for c in /tests/hidden/*; do
  [ -d "$c" ] || continue
  name=$(basename "$c")
  exp=$(cat "$c/expected.txt")
  probe /app/src/target/debug/uv "$c"
  if [ "$rc" -ne 0 ] || [ "$out" = "$exp" ] || [ -n "$out" ]; then
    fail "hidden case $name on the pre-fix tree produced the fixed output (out=[$out])"
  fi
  if ! printf '%s' "$err" | grep -q "Ignoring unsupported"; then
    fail "hidden case $name on the pre-fix tree emitted no unsupported-request warning"
  fi
done

# restore the agent's repair and rebuild so the tree is left repaired.
cp /tmp/fixed-parser.rs "$FIX_SOURCE"
"$CARGO" build -p uv >> "$LOG" 2>&1 || fail "final rebuild of the repaired tree failed"

echo "VERIFIER: PASS" >> "$LOG"
echo 1 > /logs/verifier/reward.txt
exit 0