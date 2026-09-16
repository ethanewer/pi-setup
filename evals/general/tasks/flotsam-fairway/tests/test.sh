#!/bin/bash
# Verifier for flotsam-fairway: an upstream-clone debugging task on
# duckdb/duckdb.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# printf's %c conversion writes its argument's low byte raw, so a byte in
# 128..255 yields a VARCHAR that is not valid UTF-8; displaying the value
# fails with a low-level decoding error and string functions applied to the
# result throw INTERNAL errors (+ a stack trace; strip_accents segfaults).
# The agent must also author /app/reproduce.sh, a two-sided reproduction
# that passes against the repaired engine and fails against a preserved
# snapshot of the pre-fix engine. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      only working-tree difference is the fix to
#      extension/core_functions/scalar/string/printf.cpp, the project's
#      regression data under test/sql/ is byte-identical to the pinned
#      revision, exactly one commit is reachable so the upstream fix commit
#      could not have been fetched, /app/reproduce.sh exists/executable, and
#      the harness-owned golden test and pre-fix engine snapshots are intact);
#   1. rebuilds from the repaired tree (touch the fixed source and an
#      incremental ninja -j1 relink, so any planted binary is overwritten by
#      one built from the agent's real sources) and checks the binaries are
#      real ELF executables;
#   2. copies the project's own upstream regression test for this bug out of
#      /opt/golden (the four "%c writes a single raw byte" blocks upstream
#      added to test/sql/function/string/test_printf.test; kept out of the
#      working tree during the trial, since the unittest runner reads .test
#      content from the tree at runtime) and requires it to pass through the
#      project's own runner (build/release/test/unittest);
#   3. requires the project's own test/sql/function/string/* suite to stay
#      green;
#   4. runs four authored hidden cases through the rebuilt CLI binary over
#      inputs the upstream regression does not use (embedded/continuation
#      bytes, consumer functions, vectorized rows, valid-input sanity);
#   5. runs the agent's own /app/reproduce.sh twice - against the repaired
#      engine (must exit 0 with the fixed message) and against the preserved
#      pre-fix engine at /opt/pristine/duckdb (must exit non-zero with buggy
#      markers) - and requires the two outputs to differ, so the script
#      genuinely observes the engine it is given. It then runs the script a
#      third time against an unrelated binary (/usr/bin/false) and requires a
#      non-zero exit with no canned markers, which rejects a reproduction
#      that prints pre-baked output keyed on the path instead of running the
#      engine it is passed.
#
# Reward is binary and written on every exit path (trap below; a reward file
# planted earlier in the container is removed at start so only this
# verifier's computed value can survive).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
reward=1

SRC=/app/src
PARENT_SHA=e0b375a9a0d52c40803e989ca030d05c99d56299
FIX_SHA=02f7eeb4dbc8f36c3ac3dec7132a262dbe769e35
GOLDEN_SHA=b38d0fd2a2cecf1eb527575effcad0b3b883f9797818b1fff09349db5a7500ed
GOLDEN_PARENT_SHA=15ad830b6f3673753929359e284626672ad23dc4fdf66a90fe4a05ba5d110b5c
FIX_FILE=extension/core_functions/scalar/string/printf.cpp
TEST_FILE=test/sql/function/string/test_printf.test
GOLDEN=/opt/golden/test_printf.test
GOLDEN_PARENT=/opt/golden/test_printf.parent.test
PRISTINE=/opt/pristine/duckdb
REPRO=/app/reproduce.sh

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

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M $FIX_FILE"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: the only working-tree change is to $FIX_FILE"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

if [ -z "$(git -C "$SRC" diff -- "$FIX_FILE" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented in $FIX_FILE)"
else
  echo "ok: $FIX_FILE differs from the pinned commit"
fi

tree_test=$(sha256sum < "$SRC/$TEST_FILE" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_test" = "$GOLDEN_PARENT_SHA" ]; then
  echo "ok: $TEST_FILE in the tree is byte-identical to the pinned parent revision"
else
  fail "$TEST_FILE was altered (${tree_test:-missing}); the project's regression data must stay byte-identical to the pinned revision"
fi

if [ ! -x "$REPRO" ]; then
  fail "the deliverable /app/reproduce.sh is missing or not executable"
else
  if ! grep -q "duckdb" "$REPRO" 2>/dev/null; then
    fail "/app/reproduce.sh does not invoke the engine binary; the reproduction must run the given duckdb binary"
  else
    echo "ok: /app/reproduce.sh exists, is executable and invokes the engine"
  fi
fi

golden_sha=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_sha" = "$GOLDEN_SHA" ]; then
  echo "ok: /opt/golden/test_printf.test is byte-identical to the fix-commit extraction"
else
  fail "/opt/golden/test_printf.test was altered (${golden_sha:-missing})"
fi

if [ ! -x "$PRISTINE" ]; then
  fail "the pre-fix engine snapshot /opt/pristine/duckdb is missing"
fi

# ---------- 1. rebuild from the repaired tree ---------------------------------
echo "== incremental rebuild from the repaired tree =="
# Touch the fixed source and relink: ninja must recompile it and relink
# libduckdb, the duckdb CLI and the unittest runner from the agent's actual
# sources, so any binary the agent planted (wrapper script, patched ELF) is
# overwritten by the freshly built one.
if ( cd "$SRC" && touch "$FIX_FILE" \
     && ninja -C build/release -j1 > /tmp/rebuild.log 2>&1 ); then
  echo "ok: incremental rebuild (forced relink) succeeded"
else
  fail "incremental rebuild failed"
  tail -30 /tmp/rebuild.log | sed 's/^/    /' >&2 || true
fi
is_elf() {  # is_elf BIN
  local magic
  magic=$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$magic" = "7f454c46" ]
}
for bin in "$SRC/build/release/duckdb" "$SRC/build/release/test/unittest"; do
  if [ -x "$bin" ] && is_elf "$bin"; then
    echo "ok: $bin is a real ELF executable"
  else
    fail "$bin is not a real ELF executable: $(ls -l "$bin" 2>/dev/null | awk '{print $1, $5}' || echo missing)"
  fi
done

# ---------- 2. the project's own regression test for this bug -----------------
echo "== the project's own regression test (from the upstream fix) =="
if [ "$reward" = 1 ]; then
  # The unittest runner reads .test content from the tree at runtime, so
  # overlay the golden copy (byte-pinned above) over the pinned parent's
  # version and run the file through the project's own runner.
  if cp "$GOLDEN" "$SRC/$TEST_FILE" \
     && ( cd "$SRC" && build/release/test/unittest "$TEST_FILE" > /tmp/golden.out 2>&1 ) \
     && grep -qE "All tests passed" /tmp/golden.out; then
    echo "ok: Catch summary: all tests passed for the golden regression test"
  else
    fail "the golden regression test did not pass end to end"
    tail -25 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 3. the project's own existing suite -------------------------------
echo "== the project's own string-function suite =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && build/release/test/unittest "test/sql/function/string/*" > /tmp/suite.out 2>&1 ) \
     && grep -qE "All tests passed" /tmp/suite.out; then
    echo "ok: test/sql/function/string/* green"
    grep -E "All tests passed" /tmp/suite.out | sed 's/^/    /'
  else
    fail "test/sql/function/string/* is not green"
    tail -25 /tmp/suite.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 4. authored hidden cases ------------------------------------------
echo "== hidden cases =="
n_hidden=0
n_failed=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  qf="$case"queries.txt
  [ -f "$qf" ] || { fail "hidden case $(basename "$case") has no queries.txt"; n_failed=$((n_failed+1)); continue; }
  n_hidden=$((n_hidden + 1))
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    q=${line%%$'\t'*}
    expect=${line#*$'\t'}
    # VALUE expectations compare the result row, so drive the CLI in csv mode
    # (pretty mode draws box characters around the values); ERROR expectations
    # compare the error message, which is identical in both modes.
    case "$expect" in
      VALUE:*) out=$("$SRC/build/release/duckdb" -csv -c "$q" 2>&1) ;;
      *)       out=$("$SRC/build/release/duckdb" -c "$q" 2>&1) ;;
    esac
    rc=$?
    norm=$(printf '%s' "$out" | tr -s ' \t\r\n' ' ')
    case "$expect" in
      ERROR:*) substr=${expect#ERROR:}
        if printf '%s' "$norm" | grep -Fq "$substr"; then
          echo "ok: hidden $(basename "$case") line $lineno (error) matches"
        else
          fail "hidden $(basename "$case") line $lineno: expected error containing '$substr'; got: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
          n_failed=$((n_failed+1))
        fi ;;
      VALUE:*) substr=${expect#VALUE:}
        if [ "$rc" -eq 0 ] && printf '%s' "$norm" | grep -Fq "$substr"; then
          echo "ok: hidden $(basename "$case") line $lineno (value) matches"
        else
          fail "hidden $(basename "$case") line $lineno: expected value containing '$substr'; got: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
          n_failed=$((n_failed+1))
        fi ;;
      *) fail "hidden $(basename "$case") line $lineno: bad expectation '$expect'"; n_failed=$((n_failed+1)) ;;
    esac
  done < "$qf"
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

# ---------- 5. the agent's own reproduction, run against both engines ---------
# Functional pin of the preserved pre-fix snapshot, independent of the
# agent's script: /opt/pristine/duckdb must behave exactly like the buggy
# parent build. This catches a snapshot swapped for a repaired (or patched)
# binary even if the reproduction script were somehow vacuous.
echo "== pin: /opt/pristine/duckdb still behaves as the pre-fix engine =="
if "$PRISTINE" -c "SELECT printf('%c', 255);" 2>&1 | grep -q "invalid lead byte detected"; then
  echo "ok: /opt/pristine/duckdb exhibits the pre-fix failure"
else
  fail "/opt/pristine/duckdb does not exhibit the pre-fix failure (snapshot was replaced?)"
fi

echo "== /app/reproduce.sh against the repaired engine =="
fixed_out=$(timeout 180 "$REPRO" "$SRC/build/release/duckdb" 2>&1); fixed_rc=$?
if [ "$fixed_rc" = 0 ] \
   && printf '%s' "$fixed_out" | grep -Fq "Invalid UTF8 produced by format string" \
   && ! printf '%s' "$fixed_out" | grep -Fq "INTERNAL Error"; then
  echo "ok: reproduction passes against the repaired engine"
else
  fail "reproduction did not pass against the repaired engine (rc=$fixed_rc):"
  printf '%s\n' "$fixed_out" | head -6 | sed 's/^/    /' >&2
fi

echo "== /app/reproduce.sh against the preserved pre-fix engine =="
buggy_out=$(timeout 180 "$REPRO" "$PRISTINE" 2>&1); buggy_rc=$?
if [ "$buggy_rc" != 0 ] \
   && ! printf '%s' "$buggy_out" | grep -Fq "Invalid UTF8 produced by format string" \
   && printf '%s' "$buggy_out" | grep -Eq "invalid lead byte|truncated UTF-8|INTERNAL Error|Segmentation fault|unexpectedly succeeded"; then
  echo "ok: reproduction detects the buggy pre-fix engine (rc=$buggy_rc)"
else
  fail "reproduction did not detect the pre-fix engine (rc=$buggy_rc):"
  printf '%s\n' "$buggy_out" | head -6 | sed 's/^/    /' >&2
fi

if [ "$fixed_out" = "$buggy_out" ]; then
  fail "the reproduction printed identical output on both engines; it must observe the engine it is given"
else
  echo "ok: reproduction outputs differ between the two engines"
fi

# A reproduction that prints pre-baked output keyed on the path it is given
# (or on nothing at all) satisfies the two legs above without ever observing
# the engine: e.g. `if [ "$1" = /opt/pristine/duckdb ]; then echo <buggy
# marker>; exit 1; fi; echo <fixed marker>; exit 0`. Run it against a third,
# unrelated binary that produces neither the fixed nor the buggy marker: a
# script that genuinely reads its engine must conclude "not fixed" and exit
# non-zero. A canned script prints its canned "fixed" text and exits 0
# regardless of what it is given, and is rejected here.
echo "== /app/reproduce.sh against an unrelated binary (must run it, print no marker, exit non-zero) =="
third_out=$(timeout 60 "$REPRO" /usr/bin/false 2>&1); third_rc=$?
if [ "$third_rc" -eq 0 ] \
   || printf '%s' "$third_out" | grep -Eq "Invalid UTF8 produced by format string|invalid lead byte"; then
  fail "the reproduction did not observe the engine it was given: against an unrelated binary it exited rc=$third_rc / printed a canned marker:"
  printf '%s\n' "$third_out" | head -4 | sed 's/^/    /' >&2
else
  echo "ok: reproduction fails cleanly against an unrelated binary (rc=$third_rc, no canned markers)"
fi

echo
echo "hidden cases exercised: $n_hidden, failed lines: $n_failed"
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0