#!/bin/bash
# Oracle for marlinespike-wake: applies the authored fix patch to the real
# prettier tree at /app/src, installs the reproduction deliverable under
# /app/repro, writes /app/summary.md, then proves the fix with the project's
# own jest runner against the golden regression fixtures (/opt/golden,
# extracted from the upstream fix commit at image build time) and with the
# reproduction itself. Reads only /app, /solution and /opt/golden; never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# 1) apply the fix to the tree.
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch || {
    echo "oracle: git apply failed" >&2
    exit 1
}
echo "oracle: fix applied"

# 2) the reproduction deliverable (input + expected + checker).
mkdir -p /app/repro || exit 1
cp /solution/repro/input.scss /app/repro/input.scss || exit 1
cp /solution/repro/expected.scss /app/repro/expected.scss || exit 1
cp /solution/repro/check.sh /app/repro/check.sh || exit 1
chmod +x /app/repro/check.sh || exit 1

# 3) the agent-facing reproduction must pass on the repaired tree.
if ! bash /app/repro/check.sh > /tmp/oracle-repro.log 2>&1; then
    echo "oracle: reproduction failed on repaired tree; log:" >&2
    tail -30 /tmp/oracle-repro.log >&2
    exit 1
fi

# 4) change summary.
cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Symptom
Long SCSS control-directive conditions (`@if`, `@else if`, `@while`) that chain
several comparisons with the logical keywords `and`/`or`/`not` were line-broken
right after the comparison operator, stranding `==`, `!=`, `<`, `>`, `<=` or
`>=` alone at the end of a line and pushing the right-hand operand onto the
next line. Example:

    @if $very-very-very-very-very-very-long-var ==
      0 and
      $very-very-very-long-var ==
      0

## Where the wrong decision was made
`src/language-css/print/comma-separated-value-group.js` (function
`printCommaSeparatedValueGroup`). When printing the space/line separators
between the leaf nodes of an SCSS control directive, the code kept a
non-breaking space between an operand and a *following* equality/relational
operator (`isEqualityOperatorNode(iNextNode)` / `isRelationalOperatorNode
(iNextNode)` are break keepers), but nothing kept the space between the
operator and its *following* operand. For a single comparison this never
matters, but once the directive also contains a logical keyword (`and`/`or`
/`not`) the enclosing group breaks to fit the print width, and every breakable
`line` in the group breaks -- including the one right after `==`, which
produces the dangling-operator output.

## The change
Detect that a control directive contains a logical keyword
(`hasLogicalOperator = isControlDirective && node.groups.some(isIfElseKeywordNode)`)
and, when it does, also treat an equality/relational operator as a line-break
keeper on its own position, so the comparison operator and its right-hand
operand cannot be split: `$a == 0 and` stays grouped, and the break lands
between the logical keyword and the next comparison. Single comparisons and
non-directive values are untouched.

## Verification
- `/app/repro/check.sh` runs `node bin/prettier.js /app/repro/input.scss` and
  requires byte-identical output to `/app/repro/expected.scss`;
- the project's own jest runner passes the golden SCSS at-rule regression
  fixtures for this bug (if-else.scss format 1, from /opt/golden);
- the project's own `tests/format/scss` and `tests/format/css` format suites
  pass with the fix in place.
MD

# 5) prove with the project's own runner: plant the golden regression
#    fixtures (sha-pinned at build time, never part of this task tree), run
#    the at-rule format test, then restore the tree so only the fixed source
#    file differs from the pinned parent.
mkdir -p tests/format/scss/atrule/__snapshots__
cp /opt/golden/atrule/if-else.scss tests/format/scss/atrule/if-else.scss || exit 1
cp /opt/golden/atrule/__snapshots__/format.test.js.snap \
   tests/format/scss/atrule/__snapshots__/format.test.js.snap || exit 1

if ! node_modules/.bin/jest tests/format/scss/atrule/format.test.js --runInBand --ci \
      > /tmp/oracle-golden.log 2>&1; then
    echo "oracle: golden at-rule test failed; tail:" >&2
    tail -30 /tmp/oracle-golden.log >&2
    exit 1
fi

# and the whole css/scss format surface stays green.
if ! node_modules/.bin/jest tests/format/scss tests/format/css --runInBand --ci \
      > /tmp/oracle-suite.log 2>&1; then
    echo "oracle: css/scss format suites failed; tail:" >&2
    tail -30 /tmp/oracle-suite.log >&2
    exit 1
fi

# 6) leave the tree with only the fix applied (restore the planted golden
#    copies; the verifier re-plants them itself from /opt/golden).
git checkout -- tests/format/scss/atrule/if-else.scss \
                 tests/format/scss/atrule/__snapshots__/format.test.js.snap || {
    echo "oracle: could not restore test fixtures" >&2
    exit 1
}

echo "oracle: fix applied, /app/repro + /app/summary.md written, golden and css/scss suites green"
exit 0