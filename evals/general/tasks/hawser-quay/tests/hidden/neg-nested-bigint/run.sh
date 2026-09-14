#!/bin/bash
# Hidden case: %j with NEGATIVE bigints and nested structures ("vals %j %j %j"
# with [-4n, {level: -9n}, [-12n]]). The upstream regression tests never use
# negative bigints, nested objects, or arrays-of-bigints for %j.
set -u
DIR="$1"
[ -f "$DIR/array.js" ] || { echo "no compiled formatter at $DIR"; exit 2; }
export DIR
node - <<'JS'
const dir = process.env.DIR;
const array = require(dir + '/array.js').default;
let titles;
try {
  titles = array('vals %j %j %j', [[-4n, {level: -9n}, [-12n]]]).map(r => r.title);
} catch (e) {
  console.error('neg-nested-bigint: %j title crashed -> ' + e.message);
  process.exit(1);
}
const expected = "vals \"-4n\" {\"level\":\"-9n\"} [\"-12n\"]";
if (titles[0] !== expected) {
  console.error('neg-nested-bigint: got ' + JSON.stringify(titles[0])
              + ' want ' + JSON.stringify(expected));
  process.exit(1);
}
console.log('neg-nested-bigint ok: ' + titles[0]);
JS