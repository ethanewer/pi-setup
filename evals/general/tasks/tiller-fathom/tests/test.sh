#!/usr/bin/env bash
# tiller-fathom verifier.
#
# Asserts, against the agent's container:
#   1. the deliverable reproduction files exist;
#   2. the agent's reproduction triggers the bug on the FROZEN pre-fix tree
#      (/app/pristine) and /app/repro/before.txt is exactly that observation;
#   3. the same reproduction formats with the quotes preserved on the fixed
#      tree (/app/src) and /app/repro/out.txt is exactly that observation;
#   4. the project's own quote-props regression suite passes unmodified (with
#      the golden fixture and snapshot hash-pinned so regenerating snapshots,
#      deleting fixtures or editing the test file are all caught);
#   5. a broad span of the project's own suite (tests/format/typescript)
#      still passes, proving nothing else changed;
#   6. at least two authored hidden cases (inputs exercising the same code
#      path but different shapes than the upstream fixture) show the bug on
#      the pre-fix tree and byte-match the expected fixed output.
#
# Reward is binary and written exactly once, at the end.
set -u
mkdir -p /logs/verifier
trap 'if [ ! -f /logs/verifier/reward.txt ]; then echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; echo 0 > /logs/verifier/reward.txt; fi' EXIT

fails=0
note_fail() { fails=$((fails + 1)); echo "FAIL: $*"; }

SRC_CLI=/app/src/bin/prettier.js
PRE_CLI=/app/pristine/bin/prettier.js
REPRO=/app/repro/repro.ts
BEFORE=/app/repro/before.txt
OUT=/app/repro/out.txt
PARENT_SHA=c03ab4e71c23154d6b11537eee3c938f0d0f67d3

# run_cli <cli> <file>  -> formats file with the project CLI, stdout only
run_cli() { ( cd /tmp && node "$1" --no-config --no-editorconfig "$2" 2>/dev/null ); }

# ---------------------------------------------------------------------------
echo "== [1] deliverables =="
[ -s "$REPRO" ] || note_fail "deliverable $REPRO is missing or empty"
[ -f "$BEFORE" ] || note_fail "deliverable $BEFORE is missing"
[ -f "$OUT" ] || note_fail "deliverable $OUT is missing"

# ---------------------------------------------------------------------------
echo "== [2] pre-fix tree concept: the reproduction must show the defect =="
if [ -s "$REPRO" ]; then
  pre_out="$(run_cli "$PRE_CLI" "$REPRO")"
  if [ -z "$pre_out" ]; then
    note_fail "pre-fix CLI produced no output on $REPRO (parser failure?)"
  else
    printf '%s' "$pre_out" | grep -qE '(^|[[:space:]])new\(' \
      || note_fail "pre-fix output of the reproduction contains no unquoted 'new(' — it does not exhibit the reported defect"
    printf '%s' "$pre_out" | grep -q '"new"(' \
      && note_fail "pre-fix output still quotes the new method; expected the unquoting defect"
    printf '%s\n' "$pre_out" | cmp -s - "$BEFORE" \
      || note_fail "before.txt does not match the CLI output of the untouched pre-fix tree on the reproduction"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [3] post-fix tree: the reproduction must format with quotes kept =="
if [ -s "$REPRO" ]; then
  post_out="$(run_cli "$SRC_CLI" "$REPRO")"
  if [ -z "$post_out" ]; then
    note_fail "post-fix CLI produced no output on $REPRO"
  else
    printf '%s' "$post_out" | grep -q '"new"(' \
      || note_fail "post-fix output does not preserve the quotes on the new method"
    printf '%s\n' "$post_out" | cmp -s - "$OUT" \
      || note_fail "out.txt does not match the post-fix CLI output of the reproduction"
  fi
fi

# ---------------------------------------------------------------------------
echo "== [4] golden regression files are intact (hash-pinned) =="
pin() { # <expected-sha> <path>
  expected=$1
  path=$2
  actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
  [ "$actual" = "$expected" ] || note_fail "pinned file differs from the upstream test bytes: $path"
}
pin 9f7cfe7a96edf7884d3177e6a492f89e1b2595d28bd4d6d076663aa28cfb9bb4 /app/src/tests/format/typescript/quote-props/format.test.js
pin 3ffc7a759e3829be80ffe6eabf62ccad6b5f1cb20609cca70e97f274a107c243 /app/src/tests/format/typescript/quote-props/issue-19618.ts
pin f9f8ae989241bd459666951fced807c296fe53a90c77b32d803589d54b290ba6 /app/src/tests/format/typescript/quote-props/__snapshots__/format.test.js.snap
pin 0746dcc2016275f4eced6dce7aca6c63abf0b07cf1ea09bfc5a16db2559be553 /app/src/tests/config/format-test/test-format.js
pin 40f27597aed3bce223d67fc38bff93762060df19666f1086adfeb1b868e6a843 /app/src/tests/config/format-test-setup.js

echo "== [5] pre-fix reference tree is untouched =="
[ "$(git -C /app/pristine rev-parse HEAD 2>/dev/null)" = "$PARENT_SHA" ] \
  || note_fail "pristine pre-fix tree is not on the pinned parent commit"
[ -z "$(git -C /app/pristine status --porcelain 2>/dev/null)" ] \
  || note_fail "pristine pre-fix tree has been modified"
if git -C /app/pristine cat-file -e dd5e24eabeab1f75ad573c79781e5fd408bcfad3^{commit} 2>/dev/null; then
  note_fail "the fix commit object is reachable in /app/pristine"
fi

# ---------------------------------------------------------------------------
echo "== [6] project's OWN quote-props regression suite (golden) =="
( cd /app/src && node node_modules/.bin/jest --ci --runInBand tests/format/typescript/quote-props ) >/tmp/golden.log 2>&1
golden_rc=$?
if [ "$golden_rc" -ne 0 ]; then
  note_fail "quote-props suite failed (rc=$golden_rc): $(grep -E 'Tests:|Test Suites:' /tmp/golden.log | tr '\n' ' ')"
else
  grep -q "Tests:[[:space:]]*60 passed" /tmp/golden.log \
    || note_fail "quote-props suite passed but did not run the expected 60 tests: $(grep -E 'Tests:' /tmp/golden.log | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
echo "== [7] hidden generalization cases =="
for dir in /tests/hidden/*; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  input=$(find "$dir" -maxdepth 1 -name 'input.ts' -print -quit)
  expected=$(find "$dir" -maxdepth 1 -name 'expected.ts' -print -quit)
  [ -n "$input" ] || { note_fail "hidden case $name has no input.ts"; continue; }
  cp "$input" "/tmp/hidden-$name.ts"

  pre="$(run_cli "$PRE_CLI" "/tmp/hidden-$name.ts")"
  if [ -z "$pre" ]; then
    note_fail "hidden case $name: pre-fix CLI produced no output"
  else
    printf '%s' "$pre" | grep -qE '(^|[[:space:]])new\(' \
      || note_fail "hidden case $name does not trigger the defect on the pre-fix tree"
    printf '%s' "$pre" | grep -q '"new"(' \
      && note_fail "hidden case $name shows no unquoting on the pre-fix tree"
  fi

  post="$(run_cli "$SRC_CLI" "/tmp/hidden-$name.ts")"
  if [ -n "$expected" ]; then
    printf '%s\n' "$post" | cmp -s - "$expected" \
      || note_fail "hidden case $name: formatted output does not match the expected fixed output"
  else
    printf '%s' "$post" | grep -q '"new"(' \
      || note_fail "hidden case $name: post-fix output does not preserve the quotes on the new method"
  fi
done

# ---------------------------------------------------------------------------
echo "== [8] project's own broader suite still passes (regression span) =="
( cd /app/src && node node_modules/.bin/jest --ci --runInBand tests/format/typescript ) >/tmp/ts.log 2>&1
if [ $? -ne 0 ]; then
  note_fail "tests/format/typescript failed: $(grep -E 'Tests:|Test Suites:|Snapshots:' /tmp/ts.log | tr '\n' ' ')"
else
  grep -qE "Tests:[[:space:]]*4233 passed" /tmp/ts.log \
    || note_fail "tests/format/typescript passed but the expected test mass is missing: $(grep -E 'Tests:' /tmp/ts.log | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then
  echo "PASS: reproduction verified on pre-fix and fixed trees, golden suite, regression span, hidden cases"
  echo 1 > /logs/verifier/reward.txt
else
  echo "FAIL: $fails check(s) failed" >&2
  echo 0 > /logs/verifier/reward.txt
fi
exit 0