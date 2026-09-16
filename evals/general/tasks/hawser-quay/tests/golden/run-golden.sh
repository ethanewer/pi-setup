#!/bin/bash
# Golden regression runner for hawser-quay.
#
# This is the AUTHORED hero-port of the three regression tests that the
# upstream jest fix (fix(jest-each): serialize bigint values in %j titles,
# PR #16338, commit 73f64cd) added to packages/jest-each/src/__tests__/
# array.test.ts, plus a few pre-existing formatter behaviours. The upstream
# test file itself is extracted into /opt/hawser-golden/array.test.ts at image
# build time (byte-identical, verified) and is never vendored into this tree.
#
# This copy lives under tests/ (not /opt) so that the verifier executes it
# from the read-only /tests mount: a trial agent runs as root in the same
# container as the verifier, so anything under /opt is tamperable; anything
# under /tests is a read-only bind mount and is not.
#
# Usage: run-golden.sh <dir-with-array.js>
#   Runs the three regression tests added by the upstream fix (bigint %j
#   values, cyclic %j value, values holding $ replacement patterns) against
#   the compiled formatter module found at "$1/array.js", plus the
#   pre-existing formatter behaviours the fix must not break. Exit 0 only if
#   every title matches the upstream expectations exactly.
set -u
DIR="$1"
[ -f "$DIR/array.js" ] || { echo "GOLDEN: no array.js in $DIR"; exit 1; }
export DIR
node - <<'JS'
const dir = process.env.DIR;
const array = require(dir + '/array.js').default;
let ok = true;
const check = (name, cond) => { if (!cond) { console.error('GOLDEN FAIL: ' + name); ok = false; } };

// (1) calls global test with title containing bigint param values
let t = array('expected string: %j %j %j %s', [[1n, {nested: 2n}, [3n], -4n]])
  .map(r => r.title);
check('bigint param values',
  JSON.stringify(t) === JSON.stringify(['expected string: "1n" {"nested":"2n"} ["3n"] -4n']));

// (2) calls global test with title containing a cyclic %j param value
const c = {}; c.self = c;
t = array('expected string: %j', [[c]]).map(r => r.title);
check('cyclic %j param value',
  JSON.stringify(t) === JSON.stringify(['expected string: [Circular]']));

// (3) calls global test with title containing param values holding replacement patterns
t = array('expected string: %p %p %j', [['$&', '$`', {nested: "$'" }]]).map(r => r.title);
check('replacement patterns render literally',
  JSON.stringify(t) === JSON.stringify(["expected string: \"$&\" \"$`\" {\"nested\":\"$'\"}"]))

// ---- the project's own EXISTING (pre-fix) regression tests, ported --------
// Ensures the repair broke none of the pre-existing formatter behaviours.
t = array('expected string: %s %p %s %p',
  [['string1', 'pretty1', 'string2', 'pretty2'],
   ['string1', 'pretty1', 'string2', 'pretty2']]).map(r => r.title);
check('existing %p at correct positions',
  JSON.stringify(t) === JSON.stringify(['expected string: string1 "pretty1" string2 "pretty2"',
                                        'expected string: string1 "pretty1" string2 "pretty2"']));

t = array('%s %s %s %s %s %s %s %s %s %s',
  [['hello', 1, null, undefined, 1.2, {foo: 'bar'}, ()=>{}, [],
    Number.POSITIVE_INFINITY, Number.NaN]]).map(r => r.title);
check('existing printf format',
  JSON.stringify(t) === JSON.stringify(["hello 1 null undefined 1.2 { foo: 'bar' } ()=>{} [] Infinity NaN"]));

t = array('expected index: %#', [{name: 'foo'}, {name: 'bar'}]).map(r => r.title);
check('existing %# index placeholder',
  JSON.stringify(t) === JSON.stringify(['expected index: 0', 'expected index: 1']));

t = array('expected string: %p %# $a $b $#', [{a: 'hello', b: 1}, {a: 'world', b: 1}]).map(r => r.title);
check('existing $variable mix',
  JSON.stringify(t) === JSON.stringify(["expected string: {\"a\": \"hello\", \"b\": 1} 0 $a $b $#",
                                        "expected string: {\"a\": \"world\", \"b\": 1} 1 $a $b $#"]));

t = array('expected escaped: %%e', [['x']]).map(r => r.title);
check('existing escaped placeholder',
  JSON.stringify(t) === JSON.stringify(['expected escaped: %e']));

if (!ok) { process.exit(1); }
console.log('GOLDEN: all 3 upstream regression tests + existing suite PASS');
JS