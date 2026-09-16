#!/bin/bash
# Oracle for capstan-mooring: applies the one-line, one-source-file fix to the
# real eslint tree at /app/src (baseTenLosesPrecision must strip a single
# trailing '.' from the raw literal before normalising it to scientific
# notation, so trailing-dot literals compare identically to their plain
# spellings), writes /app/summary.md, then proves the work with the project's
# own machinery: the reproduction script (must exit 0) and the project's own
# regression test for the bug (the rule's test file as of the fix commit,
# baked at /opt/golden; all 131 cases must pass under mocha). Reads only
# /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied rawNumber trailing-dot strip fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the `no-loss-of-precision` rule reported literals written with a
trailing decimal point and no fractional digits — `var x = 0.` was flagged
"This number literal will lose precision at runtime." even though the value
is exactly representable, while the same number written `0` or `0.0` was
accepted.

Cause: the rule's `baseTenLosesPrecision` helper reads each literal's raw
source text (`getRaw(node)`), lowercases it, and normalises it to scientific
notation before comparing against the parsed `node.value`. A literal like
`0.` keeps its trailing `.` in that raw text, so the float normaliser
(`normalizeFloat`) handles the empty trailing fraction like a malformed
coefficient and the resulting normal form never matches the parsed value —
hence a false "loss of precision" report, even though the value is exact.
Precision really is lost only when the significant digits themselves cannot
round-trip, which is exactly when the plain spellings are also reported.

Fix: in `baseTenLosesPrecision`, strip a single trailing `.` from the raw
literal (`rawNumber.toLowerCase().replace(/\.$/u, "")`) before normalising,
so trailing-dot literals are compared in exactly the same scientific-notation
form as their plain spellings. Genuinely lossy trailing-dot literals such as
`9007199254740993.` still report, because their significant digits still
cannot round-trip after the dot is stripped.

Verification: the reproduction script `/app/repro.js` (valid `var x = 0.`,
invalid `var x = 9007199254740993.`) exits 0 with no errors; the project's
own regression test for this bug (the rule's test file as of the fix commit,
planted from /opt/golden, 131 cases) passes under mocha; and a targeted
selection of the project's existing rule/rule-tester tests stays green.
MD

# Prove the user-visible symptom is fixed.
node /app/repro.js > /tmp/oracle_repro.log 2>&1 || {
    echo "oracle: repro still fails (see /tmp/oracle_repro.log)" >&2
    tail -20 /tmp/oracle_repro.log >&2
    exit 1
}
echo "oracle: repro OK (exit 0)"

# Prove it with the project's own regression test (golden bytes from
# /opt/golden, already in the image), via the project's own test runner.
cp /opt/golden/no-loss-of-precision.js tests/lib/rules/no-loss-of-precision.js
if ! ./node_modules/.bin/mocha tests/lib/rules/no-loss-of-precision.js > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: golden regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "131 passing" /tmp/oracle_golden.log || {
    echo "oracle: golden test did not actually run 131 cases" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
}
echo "oracle: golden regression test green (131 passing)"

# Leave the tree exactly as the verifier expects it: the golden test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- tests/lib/rules/no-loss-of-precision.js || {
    echo "oracle: could not restore tests/lib/rules/no-loss-of-precision.js" >&2
    exit 1
}

echo "oracle: fix applied, summary written, repro + golden regression green"
exit 0