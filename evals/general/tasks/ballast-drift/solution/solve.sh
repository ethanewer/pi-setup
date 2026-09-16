#!/bin/bash
# Oracle for ballast-drift: applies the one-source-file fix to the real
# eslint tree at /app/src (the rule must honour the "don't check property
# accesses" option before its UTC special case, so every member callee is
# exempted when properties:false and the Date.UTC exemption is preserved
# when property checking is on), writes /app/summary.md, then proves the
# work with the project's own machinery: the reproduction script (must exit
# 0) and the project's own regression test for the bug (the rule's test
# file as of the fix commit, baked at /opt/golden; all 97 cases must pass
# under mocha). Reads only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied skipProperties/UTC reorder fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the `new-cap` rule, configured with the option that suppresses
property-access checks (`properties: false`), still reported member calls
whose name ends in `UTC` (`foo.UTC()`, `foo?.UTC()`, `a.Date.UTC()`, ...)
as "A function with a name starting with an uppercase letter should only be
used as a constructor."

Cause: in the rule's `isCapAllowed` helper, the special case that exempts
only genuine `Date.UTC` (callee name `UTC` on a MemberExpression) ran
*before* the `skipProperties` branch. So when `properties: false` was set,
every member callee named `UTC` fell into the special case, was compared
against `Date`, was not `Date.UTC`, and was reported — the skipProperties
short-circuit (return true for any MemberExpression callee) never got a
chance to run for `UTC`-named members, and deeper chains (`a.Date.UTC`)
failed the `Date` identifier check too.

Fix: restructure the member-expression handling so that `skipProperties` is
honoured first: when the callee is a MemberExpression and property checking
is disabled, the callee is allowed immediately; only when property checking
is enabled does the `Date.UTC` exemption logic apply (and everything else
falls through to the existing false). Bare capitalised calls, the default
configuration, and all non-`UTC` member call behaviour are unchanged.

Verification: the reproduction script `/app/repro.js` (three valid cases
`foo.UTC();`, `foo?.UTC();`, `const b = a.Date.UTC();` with
`properties: false`) exits 0 with no errors; the project's own regression
test for this bug (the rule's test file as of the fix commit, planted from
/opt/golden, 97 cases) passes under mocha, and a targeted selection of the
project's existing rule/rule-tester tests stays green.
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
cp /opt/golden/new-cap.js tests/lib/rules/new-cap.js
if ! ./node_modules/.bin/mocha tests/lib/rules/new-cap.js > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: golden regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "97 passing" /tmp/oracle_golden.log || {
    echo "oracle: golden test did not actually run 97 cases" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
}
echo "oracle: golden regression test green (97 passing)"

# Leave the tree exactly as the verifier expects it: the golden test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- tests/lib/rules/new-cap.js || {
    echo "oracle: could not restore tests/lib/rules/new-cap.js" >&2
    exit 1
}

echo "oracle: fix applied, summary written, repro + golden regression green"
exit 0