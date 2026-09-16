#!/bin/bash
# Oracle for stern-roadstead: fixes the real jestjs/jest tree at /app/src for
# the `.each` title-interpolation defect (issue #16345): template keys are
# joined into the `$variable` alternation without escaping and in insertion
# order, so a heading with regex metacharacters like `count(*)` throws
# SyntaxError at table construction and `.`/`|` headings interpolate the wrong
# text. The fix (single source file, applied via /solution/fix.patch) escapes
# every key with jest-regex-util's escapeStrForRegex and sorts keys
# longest-first.
#
# The oracle creates every declared deliverable (/app/repro.sh, /app/summary.md,
# the fixed /app/src), then proves the work with the project's own test runner:
# the upstream regression test from /opt/golden plus the project's own full
# jest-each unit suite. Reads only /app, /solution and /opt/golden, never
# /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export FORCE_COLOR=1
JEST="node ./packages/jest-cli/bin/jest.js"

# 1) apply the fix to the working tree (the only file that may differ from the
#    pinned parent commit).
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied title-interpolation fix"

# 2) write the reproduction deliverable (canonical behavioral repro) and the
#    change summary.
cp /solution/repro.sh /app/repro.sh
chmod 755 /app/repro.sh
cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Symptom
`test.each` / `it.each` tables whose column headings contain characters that
are special in regular expressions blow up before any test runs. A heading
like `count(*)` makes the whole table throw

    SyntaxError: Invalid regular expression: /\$(count(*)|expected)[.\w]*/g: Nothing to repeat

and less destructive headings misbehave silently: a dot in a heading acts as a
wildcard (matching any character) and a vertical bar splits the alternation,
so `$variable` titles interpolate the wrong value.

## Where the defect lives
`packages/jest-each/src/table/interpolation.ts`, `interpolateVariables`. It
built the `$variable` alternation as

    new RegExp(`\\$(${Object.keys(template).join('|')})[.\\w]*`, 'g')

i.e. the heading keys were pasted into a regular expression verbatim, in
object-key insertion order, with no escaping and no length ordering.

## Fix
- collect the template keys, drop empty ones, and sort them longest-first so
  an overlapping heading (e.g. `a|b` vs `a`) always wins regardless of
  insertion order;
- escape every key with jest-regex-util's `escapeStrForRegex` before joining
  them into the alternation, so all regex metacharacters are matched
  literally;
- when the template has no usable keys, fall back to replacing only `$#`.

This restores the existing behaviours: plain `$key` and `$key.path`
interpolation, `$#` index substitution, and pretty-format rendering of
non-primitive values are untouched.

## Verification
- `/app/repro.sh` prints exactly `rows: 1 is one` / `rows: 2 is two` and
  exits 0 (on the unfixed tree the same script fails);
- the upstream regression test for this bug (extracted from the fixing commit
  into `/opt/golden`) passes with the project's own test runner;
- the project's own full `jest-each` unit suite (array, index, template
  tests) stays green.
MD

# 3) refresh the built package so `build/` reflects the fixed source.
rm -rf node_modules/.cache
if ! yarn build:js > /tmp/oracle-build.log 2>&1; then
    echo "oracle: yarn build:js failed; tail:" >&2
    tail -30 /tmp/oracle-build.log >&2
    exit 1
fi

# 4) the reproduction must now pass with the exact expected output.
out=$(/app/repro.sh 2>/tmp/oracle-repro.err); rc=$?
if [ "$rc" -ne 0 ]; then
    echo "oracle: repro.sh failed after the fix (rc=$rc); stderr:" >&2
    head -10 /tmp/oracle-repro.err >&2
    exit 1
fi
if [ "$out" != "rows: 1 is one
rows: 2 is two" ]; then
    echo "oracle: repro.sh output mismatch:" >&2
    printf '%s' "$out" | od -c | head -8 >&2
    exit 1
fi
echo "oracle: repro OK (rc=0, exact output)"

# 5) plant the upstream regression test for this bug (golden bytes from
#    /opt/golden, baked into the image at build time, sha256-pinned) and run
#    it with the project's own test runner; restore the tree file afterwards.
cp packages/jest-each/src/__tests__/template.test.ts /tmp/oracle-template.test.ts
cp /opt/golden/template.test.ts packages/jest-each/src/__tests__/template.test.ts
if ! $JEST packages/jest-each/src/__tests__/template.test.ts --runInBand --silent \
     > /tmp/oracle-golden.log 2>&1; then
    echo "oracle: golden regression test did not pass; tail:" >&2
    grep -m5 -A12 "●" /tmp/oracle-golden.log >&2
    mv /tmp/oracle-template.test.ts packages/jest-each/src/__tests__/template.test.ts
    exit 1
fi
mv /tmp/oracle-template.test.ts packages/jest-each/src/__tests__/template.test.ts
echo "oracle: golden regression test passed"

# 6) the project's own existing jest-each unit suite must stay green.
if ! $JEST packages/jest-each/src/__tests__/array.test.ts \
     packages/jest-each/src/__tests__/index.test.ts \
     packages/jest-each/src/__tests__/template.test.ts \
     --runInBand --silent > /tmp/oracle-suite.log 2>&1; then
    echo "oracle: existing jest-each unit suite did not pass; tail:" >&2
    tail -30 /tmp/oracle-suite.log >&2
    exit 1
fi
echo "oracle: existing jest-each unit suite green"

echo "oracle: fix applied, repro + golden + existing suite green"
exit 0