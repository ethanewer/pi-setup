#!/bin/bash
# Verifier for brackish-deepwater: an upstream-clone debugging task on
# duckdb/duckdb.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the parallel CSV reader double-counts rows at buffer boundaries when a
# file's lines end with CR CR LF ('\r\r\n'), so a parallel scan returns more
# rows than the file contains (10,002 vs 10,000 at buffer_size=4096 on the
# shipped 10,000-row fixture) while the sequential scan is correct. The agent
# must also deliver its own reproduction script /app/repro.sh whose contract
# is to print REPRO-PASS iff a parallel and a sequential read of the fixture
# both equal the true row count. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      single-commit object store does not contain the upstream fix commit,
#      the overlaid regression-test and fixture files are byte-identical to
#      the upstream bytes, exactly one source file under src/ differs and
#      nothing else in the repository changed);
#   1. deletes the project binaries and rebuilds from the repaired tree
#      (incremental, ~30 s per cycle at 1 CPU) and requires the project's own
#      regression test test_rrrn_parallel.test to pass through the project's
#      own runner (build/release/test/unittest), plus the project's own
#      parallel-CSV suites to stay green, and both project binaries to be
#      real ELF executables afterwards;
#   2. executes the agent's /app/repro.sh twice: pointed at the pre-fix
#      engine snapshot /opt/pre-fix/duckdb it must print REPRO-FAIL (the
#      reproduction genuinely detects the bug), and pointed at the repaired
#      engine it must print REPRO-PASS;
#   3. runs authored hidden cases (own \r\r\n fixtures with different row
#      counts/layouts and buffer sizes the upstream test does not use)
#      through the repaired CLI, asserting exact counts/aggregates, AND runs
#      each hidden check against the pre-fix snapshot, requiring it to
#      produce a different value (i.e. the check detects the bug pre-fix).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=916aeeb64b0bd2e0f172266ac485daa929a4af98
FIX_SHA=17b972423bc2ed597ab310c7b6369ff0949356ad
GOLDEN_SHA=53b2116b7db9ab2e6b4e2df763c2d5e407f3e15fad0a499d29e74ab558b9d277
FIXTURE_SHA=4a1daa3ff6dcaaa639c81f710c934ae2b9c33ddef642510bc02c6ffabb99ed99
GOLDEN=test/sql/copy/csv/parallel/test_rrrn_parallel.test
FIXTURE=data/csv/test/rrrn_parallel_test.csv
PRE_FIX=/opt/pre-fix/duckdb

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

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null | tr -d '[:space:]')
if [ "$ncommits" = "1" ]; then
  echo "ok: single-commit object store ($ncommits commit)"
else
  fail "object store has $ncommits commits; expected exactly 1"
fi

for pair in "$GOLDEN|$GOLDEN_SHA" "$FIXTURE|$FIXTURE_SHA"; do
  rel=${pair%%|*}
  want=${pair#*|}
  got=$(sha256sum < "$SRC/$rel" 2>/dev/null | cut -d' ' -f1)
  if [ "$got" = "$want" ]; then
    echo "ok: $rel is byte-identical to the upstream file"
  else
    fail "$rel was altered (${got:-missing})"
  fi
done

modified=$(git -C "$SRC" diff --name-only HEAD -- src/ 2>/dev/null | grep -v '^$' | sort)
nmod=$(printf '%s\n' "$modified" | grep -c . || true)
if [ "$nmod" = "1" ]; then
  echo "ok: exactly one source file under src/ differs: $modified"
else
  fail "expected exactly one modified source file under src/; found ${nmod:-0}: $(printf '%s ' $modified)"
fi
if [ -n "$modified" ] && [ -z "$(git -C "$SRC" diff -- "$modified" 2>/dev/null || true)" ]; then
  fail "the modified file is empty of changes (no fix was implemented)"
else
  echo "ok: $modified contains a real diff"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected_lines="$porcelain"
modline=$(printf '%s\n' "$expected_lines" | grep -E "^ M src/" | head -1)
n_modline=$(printf '%s\n' "$expected_lines" | grep -cE "^ M src/" || true)
n_other=$(printf '%s\n' "$expected_lines" | grep -vE "^ M src/|^\?\? $GOLDEN$|^\?\? $FIXTURE$" | grep -c . || true)
if [ "$n_modline" = "1" ] && [ "$n_other" = "0" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the two overlaid upstream files"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -12 | sed 's/^/    /' >&2
fi

# ---------- 1. rebuild from the repaired tree and run the project's tests -----
echo "== rebuild from the repaired tree =="
# Delete the project binaries and rebuild: ninja must recompile the modified
# source and relink libduckdb, the duckdb CLI and the unittest runner, so any
# binary the agent planted (wrapper script, ELF decoy, stale build) is
# replaced by one freshly linked from the agent's actual sources.
if ( cd "$SRC" \
     && rm -f build/release/duckdb build/release/test/unittest \
     && [ -z "$modified" ] || touch "$modified" \
     && ninja -C build/release -j2 > /tmp/rebuild.log 2>&1 ); then
  echo "ok: incremental rebuild (forced relink) succeeded"
else
  fail "incremental rebuild failed"
  tail -40 /tmp/rebuild.log 2>/dev/null | sed 's/^/    /' >&2 || true
fi

# The binaries must be real ELF executables produced by the relink above, not
# scripts the agent substituted for the project's own engine and runner.
is_elf() {  # is_elf BIN
  local magic
  magic=$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$magic" = "7f454c46" ]
}
for bin in "$SRC/build/release/duckdb" "$SRC/build/release/test/unittest"; do
  if [ -f "$bin" ] && is_elf "$bin"; then
    echo "ok: $bin is a real ELF executable"
  else
    fail "$bin is not a real ELF executable: $(ls -l "$bin" 2>/dev/null | awk '{print $1, $5}' || echo missing)"
  fi
done

echo "== the project's own regression test for this bug =="
if [ "$reward" = 1 ]; then
  ( cd "$SRC" && build/release/test/unittest "$GOLDEN" > /tmp/golden.out 2>&1 )
  if grep -qE "All tests passed" /tmp/golden.out 2>/dev/null; then
    echo "ok: golden regression test passed end to end"
  else
    fail "the golden regression test did not pass"
    tail -25 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "== the project's own parallel-CSV suites =="
suite_ok=1
if [ "$reward" = 1 ]; then
  for flt in \
      "test/sql/copy/csv/parallel/test_parallel_csv.test" \
      "test/sql/copy/csv/parallel/csv_parallel_buffer_size.test" \
      "test/sql/copy/csv/parallel/csv_parallel_null_option.test" \
      "test/sql/copy/csv/parallel/test_parallel_error_messages.test" \
      "test/sql/copy/csv/parallel/test_multiple_files.test" \
      "test/sql/copy/csv/parallel/parallel_csv_union_by_name.test" \
      "test/sql/copy/csv/parallel/parallel_csv_hive_partitioning.test"; do
    if ( cd "$SRC" && build/release/test/unittest "$flt" > "/tmp/suite-$(basename "$flt" | tr '/.' '__').out" 2>&1 ) \
       && grep -qE "All tests passed" "/tmp/suite-$(basename "$flt" | tr '/.' '__').out"; then
      echo "ok: suite '$flt' green"
    else
      fail "suite '$flt' is not green"
      tail -12 "/tmp/suite-$(basename "$flt" | tr '/.' '__').out" 2>/dev/null | sed 's/^/    /' >&2 || true
      suite_ok=0
    fi
  done
fi

# ---------- 2. the agent's own reproduction, both directions ------------------
echo "== /app/repro.sh against the pre-fix engine and the repaired engine =="
if [ ! -x /app/repro.sh ]; then
  fail "/app/repro.sh is missing or not executable"
elif [ "$reward" = 1 ]; then
  preout=$(bash /app/repro.sh "$PRE_FIX" 2>&1 || true)
  if printf '%s\n' "$preout" | grep -q "REPRO-PASS"; then
    fail "/app/repro.sh printed REPRO-PASS on the pre-fix engine (it does not detect the bug)"
  else
    echo "ok: /app/repro.sh detects the bug on the pre-fix engine"
  fi
  fixout=$(bash /app/repro.sh 2>&1 || true)
  if printf '%s\n' "$fixout" | grep -q "REPRO-PASS"; then
    echo "ok: /app/repro.sh passes against the repaired engine"
  else
    fail "/app/repro.sh did not print REPRO-PASS against the repaired engine: $(printf '%s' "$fixout" | head -3 | tr '\n' ' ')"
  fi
fi

# ---------- 3. authored hidden cases -----------------------------------------
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
    line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    q=${line%%$'\t'*}
    expect=${line#*$'\t'}
    case "$expect" in
      VALUE:*)
        want=${expect#VALUE:}
        # repaired engine must produce exactly the expected value
        r_out=$("$SRC/build/release/duckdb" -csv -c "$q" 2>&1)
        r_val=$(printf '%s\n' "$r_out" | grep -E '^[0-9,-]+$' | head -1)
        if [ "$r_val" = "$want" ]; then
          echo "ok: hidden $(basename "$case") line $lineno (repaired) = $want"
        else
          fail "hidden $(basename "$case") line $lineno: repaired engine returned '${r_val:-<empty>}', expected '$want'"
          n_failed=$((n_failed+1))
        fi
        # pre-fix engine must produce a DIFFERENT value (this check bites)
        p_out=$("$PRE_FIX" -csv -c "$q" 2>&1)
        p_val=$(printf '%s\n' "$p_out" | grep -E '^[0-9,-]+$' | head -1)
        if [ -n "$p_val" ] && [ "$p_val" = "$want" ]; then
          fail "hidden $(basename "$case") line $lineno: pre-fix engine also returns '$want' (this check does not detect the bug)"
          n_failed=$((n_failed+1))
        else
          echo "ok: hidden $(basename "$case") line $lineno detects the bug pre-fix (pre-fix returned '${p_val:-<empty>}')"
        fi
        ;;
      *) fail "hidden $(basename "$case") line $lineno: bad expectation '$expect'"; n_failed=$((n_failed+1)) ;;
    esac
  done < "$qf"
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo
echo "hidden cases exercised: $n_hidden, failed lines: $n_failed"
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0