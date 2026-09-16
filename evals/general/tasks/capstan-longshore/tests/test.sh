#!/bin/bash
# Verifier for capstan-longshore: an upstream-clone debugging task on
# duckdb/duckdb.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# executing a prepared statement that uses named parameters, when some of the
# declared parameters are not supplied, reports the missing names in hash-map
# iteration order instead of declaration order (PreparedStatement
#::MissingValuesException collects them into an identifier_set_t / unordered
# set). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, the
#      only working-tree differences are the fix to
#      src/include/duckdb/main/prepared_statement.hpp and the byte-identical
#      golden regression file the image overlaid into
#      test/sql/prepared/prepared_named_param.test);
#   1. rebuilds from the repaired tree (incremental) and requires the
#      project's own regression test prepared_named_param.test to pass through
#      the project's own runner (build/release/test/unittest), plus the whole
#      project's own prepared-statement sqllogictest suite to stay green;
#   2. runs the exact issue reproduction through the CLI binary and requires
#      the missing parameters to be reported in declaration order;
#   3. runs four authored hidden cases driving the same code path from inputs
#      the upstream test does not use (different name sets, gap positions, a
#      repeated parameter name, a fully-empty supply, and an all-supplied
#      sanity check), each asserting the exact ordered error message.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=9c21294d984dfe9a1da5d055b5fce3e8a0d634b2
FIX_SHA=c306b47b18095823f22774a972e7cda1170f87a0
GOLDEN_SHA=14da4c35447fb14b92f616ef5356a316f55365505a286647a2f1171f99f7a928
GOLDEN=/opt/golden/prepared_named_param.test
SRC_TEST=test/sql/prepared/prepared_named_param.test
HEADER_SRC=src/include/duckdb/main/prepared_statement.hpp

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

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

# Only two working-tree differences are tolerated: the fix to the
# prepared-statement header and the golden regression file the image overlaid.
saw_header=0
saw_golden=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  path=${line:3}
  case "$path" in
    "$HEADER_SRC")
      if [ "${line:0:2}" = " M" ] || [ "${line:0:2}" = "M " ] || [ "${line:0:2}" = "MM" ]; then
        saw_header=1
      else
        echo "FAIL: unexpected status for $HEADER_SRC: $line" >&2; bad_tree=1
      fi ;;
    "$SRC_TEST")
      if [ "${line:0:2}" = " M" ] || [ "${line:0:2}" = "M " ] || [ "${line:0:2}" = "MM" ]; then
        saw_golden=1
      else
        echo "FAIL: unexpected status for $SRC_TEST: $line" >&2; bad_tree=1
      fi ;;
    *)
      echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_header" = 0 ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented in $HEADER_SRC)"
fi
if [ "$saw_golden" = 0 ]; then
  fail "$SRC_TEST is not a working-tree modification (it was reverted; the golden regression file must stay in the tree)"
else
  echo "ok: $SRC_TEST is the overlaid golden regression file"
fi

if [ -z "$(git -C "$SRC" diff HEAD -- "$HEADER_SRC" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: $HEADER_SRC differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$SRC_TEST" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: $SRC_TEST is byte-identical to the fix-commit regression test"
else
  fail "$SRC_TEST was altered (${tree_golden:-missing}); it must stay byte-identical to the golden file"
fi

if [ ! -s /app/explanation.md ]; then
  fail "the deliverable /app/explanation.md is missing or empty"
else
  if ! grep -qiE "order" /app/explanation.md || ! grep -qiE "parameter" /app/explanation.md; then
    fail "/app/explanation.md does not actually discuss the parameter ordering semantics"
  else
    echo "ok: /app/explanation.md exists and discusses the root cause"
  fi
fi

# ---------- 1. rebuild and run the project's own suites -----------------------
echo "== incremental rebuild from the repaired tree =="
# The engine and the test runner that the checks below execute must be products
# of THIS tree's own build. Remove them so ninja has to regenerate them from
# the sources (they are real build outputs, so an already-built tree relinks
# them in seconds), and afterwards require them to be ELF executables: a wrapper
# script or a staged fake masquerading as the engine or the runner cannot
# survive the rebuild, and if one is planted anyway it is rejected.
rm -f "$SRC/build/release/duckdb" "$SRC/build/release/test/unittest"
if ( cd "$SRC" && ninja -C build/release -j1 > /tmp/rebuild.log 2>&1 ); then
  echo "ok: incremental rebuild succeeded"
else
  fail "incremental rebuild failed"
  tail -30 /tmp/rebuild.log | sed 's/^/    /' >&2 || true
fi
for bin in "$SRC/build/release/duckdb" "$SRC/build/release/test/unittest"; do
  if [ ! -x "$bin" ]; then
    fail "$bin is missing after the rebuild"
    continue
  fi
  magic=$(head -c 4 "$bin" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  if [ "$magic" != "7f454c46" ]; then
    fail "$bin is not an ELF executable (it looks like a wrapper script or a fake)"
  fi
done

echo "== the project's own regression test for this bug =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && build/release/test/unittest "$SRC_TEST" > /tmp/golden.out 2>&1 ) \
     && grep -qE "All tests passed" /tmp/golden.out; then
    echo "ok: Catch summary: all tests passed for the golden regression test"
  else
    fail "the golden regression test did not pass end to end"
    tail -25 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "== the project's own prepared-statement suite =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && build/release/test/unittest "test/sql/prepared/*" > /tmp/suite.out 2>&1 ) \
     && grep -qE "All tests passed" /tmp/suite.out; then
    echo "ok: test/sql/prepared/* green"
    grep -E "test cases:" /tmp/suite.out | sed 's/^/    /'
  else
    fail "test/sql/prepared/* is not green"
    tail -25 /tmp/suite.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 2. the exact issue reproduction -----------------------------------
echo "== the issue reproduction: missing parameters in declaration order =="
if [ "$reward" = 1 ]; then
  out=$("$SRC/build/release/duckdb" -c 'PREPARE q03 AS SELECT $aa, $bb, $cc, $dd, $ee; EXECUTE q03(aa := 1, bb := 2);' 2>&1) || true
  if printf '%s\n' "$out" | grep -Fq "parameters: cc, dd, ee"; then
    echo "ok: reproduction reports the missing parameters in declaration order"
    printf '%s\n' "$out" | sed 's/^/    /'
  else
    fail "reproduction did not report the missing parameters in declaration order"
    printf '%s\n' "$out" | head -3 | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 3. authored hidden cases ------------------------------------------
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
    # (pretty mode draws box characters between the values and no plain
    # whitespace sequence joins the numbers); ERROR expectations compare the
    # error message, which is identical in both modes.
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

echo
echo "hidden cases exercised: $n_hidden, failed lines: $n_failed"
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0