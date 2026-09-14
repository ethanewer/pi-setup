#!/bin/bash
# Hidden case: a bigint inside a MIXED object compared against an
# independently computed JSON expectation ('v %j' with a row object holding
# number, bigint and null fields). The upstream regression tests never put a
# bigint inside an object in a %j title, nor alongside null/number fields.
set -u
DIR="$1"
[ -f "$DIR/array.js" ] || { echo "no compiled formatter at $DIR"; exit 2; }
export DIR
node - <<'JS'
const dir = process.env.DIR;
const array = require(dir + '/array.js').default;
let titles;
try {
  titles = array('v %j', [[{a: 1, b: 2n, c: null}]]).map(r => r.title);
} catch (e) {
  console.error('mixed-object-bigint: %j title crashed -> ' + e.message);
  process.exit(1);
}
const expected = 'v ' + JSON.stringify({a: 1, b: 2n, c: null},
  (_, entry) => typeof entry === 'bigint' ? entry.toString() + 'n' : entry);
if (titles[0] !== expected) {
  console.error('mixed-object-bigint: got ' + JSON.stringify(titles[0])
              + ' want ' + JSON.stringify(expected));
  process.exit(1);
}
console.log('mixed-object-bigint ok: ' + titles[0]);
JS