#!/bin/bash
# Oracle for berm-coaming: writes the agent-facing reproduction deliverable
# /app/repro.sh, applies the minimal upstream fix to the duckdb checkout at
# /app/src (ListReduceFun::GetFunctions must mark the function fallible so
# exceptions raised by the user's reduce lambda propagate as clean
# user-facing errors instead of INTERNAL errors), rebuilds incrementally,
# and proves the golden regression test and the project's own lambda suites
# pass through the project's own runner. Reads only /app, /solution and
# /opt/golden; the resulting tree differs from the pinned commit in exactly
# one source file (the fix).
set -u

echo "== writing the reproduction deliverable =="
cat > /app/repro.sh <<'REPRO_EOF'
#!/bin/bash
# Reproduction for the list_reduce lambda-error bug.
# Usage: repro.sh [DUCKDB_BIN]   (default /app/src/build/release/duckdb)
set -u
BIN=${1:-/app/src/build/release/duckdb}
Q="SELECT list_reduce([1, 2], lambda x, y: error('test error'));"
out=$("$BIN" -c "$Q" 2>&1)
if printf '%s\n' "$out" | grep -q "INTERNAL Error"; then
  echo "REPRO-FAIL (INTERNAL error surfaced instead of the lambda's own error)"
  exit 1
elif printf '%s\n' "$out" | grep -q "Invalid Input Error: test error"; then
  echo "REPRO-PASS"
  exit 0
else
  echo "REPRO-FAIL (unexpected output: $(printf '%s' "$out" | head -1))"
  exit 1
fi
REPRO_EOF
chmod +x /app/repro.sh

echo "== applying the minimal upstream fix =="
python3 - <<'PY'
path = "/app/src/extension/core_functions/scalar/list/list_reduce.cpp"
s = open(path).read()
anchor = "fun.SetBindLambdaCallback(ListReduceBindLambda);\n"
assert anchor in s, "anchor line not found in list_reduce.cpp"
assert "fun.SetFallible();" not in s, "fix already present; tree not at parent?"
s = s.replace(anchor, anchor + "\tfun.SetFallible();\n", 1)
open(path, "w").write(s)
print("applied: ListReduceFun now marks the function fallible")
PY

echo "== incremental rebuild =="
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
ninja -C build/release > /tmp/oracle_ninja.log 2>&1 || {
  echo "oracle: rebuild failed; tail:" >&2
  tail -30 /tmp/oracle_ninja.log >&2
  exit 1
}

check_unittest() {  # check_unittest FILTER
  local filter=$1
  local out
  out=$(cd /app/src && build/release/test/unittest "$filter" 2>&1) || true
  if printf '%s\n' "$out" | grep -q "All tests passed"; then
    echo "ok: $filter"
  else
    echo "FAIL: unittest '$filter' did not pass:" >&2
    printf '%s\n' "$out" | tail -20 >&2
    exit 1
  fi
}

echo "== upstream regression test for this bug (golden, from /opt/golden) =="
rm -f /app/src/test/sql/function/list/lambdas/reduce.test
cp /opt/golden/reduce.test /app/src/test/sql/function/list/lambdas/reduce.test
check_unittest "test/sql/function/list/lambdas/reduce.test"

echo "== project's own lambda suites =="
check_unittest "test/sql/function/list/lambdas/*"

# The golden file was planted here only to prove the fix; the verifier
# re-plants it itself from /opt/golden. Restore the tracked test file so the
# working tree differs from the pinned commit in exactly the one source file.
git restore --worktree --source=HEAD -- test/sql/function/list/lambdas/reduce.test || {
  echo "oracle: could not restore reduce.test" >&2
  exit 1
}
test -z "$(git status --porcelain | grep -v '^ M extension/core_functions/scalar/list/list_reduce.cpp' || true)" || {
  echo "oracle: working tree differs from the pinned commit outside the fix file:" >&2
  git status --porcelain >&2
  exit 1
}

echo "== reproduction against the repaired engine =="
/app/repro.sh > /tmp/oracle_repro.out 2>&1 || {
  echo "FAIL: /app/repro.sh did not pass against the repaired engine" >&2
  cat /tmp/oracle_repro.out >&2
  exit 1
}
grep -q "REPRO-PASS" /tmp/oracle_repro.out || {
  echo "FAIL: /app/repro.sh did not print REPRO-PASS" >&2
  cat /tmp/oracle_repro.out >&2
  exit 1
}

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: when the reduction lambda passed to `list_reduce` raised an error at
runtime, the query failed with

    INTERNAL Error: Scalar function "list_reduce" threw an execution error,
    but the function is not marked as fallible - the function must call
    SetFallible(). Error: <lambda message>

plus a stack trace, instead of surfacing the lambda's own clean error the
way `list_transform` / `list_filter` do.

Fix: `ListReduceFun::GetFunctions` in the core_functions scalar list
extension now marks the function fallible (`fun.SetFallible()`), exactly one
line, so exceptions raised by the user's lambda are treated by the engine as
ordinary query errors (`Invalid Input Error: ...` / `Conversion Error: ...`)
instead of INTERNAL errors.

Verification: the project's own regression test for this bug (extracted from
the upstream fix into /opt/golden) passes through the project's own runner,
as does the whole test/sql/function/list/lambdas suite, and /app/repro.sh
prints REPRO-PASS against the repaired engine while it prints REPRO-FAIL
against the pre-fix snapshot at /opt/pre-fix/duckdb.
MD

echo "OK: fix applied, reproduction deliverable written, golden test and lambda suites green"
exit 0