#!/bin/bash
# Hidden case: $-replacement patterns spread across %p AND %j slots
# (['$&', '$$', "$'", '$`', '$&'] with title 't: %p %p %p %p %j'). The
# upstream regression test only uses three slots (%p %p %j) with one $ pattern
# each; this mixes all four pattern characters in both placeholder kinds.
set -u
DIR="$1"
[ -f "$DIR/array.js" ] || { echo "no compiled formatter at $DIR"; exit 2; }
export DIR
node - <<'JS'
const dir = process.env.DIR;
const array = require(dir + '/array.js').default;
let titles;
try {
  titles = array('t: %p %p %p %p %j', [['$&', '$$', "$'", '$`', '$&']])
    .map(r => r.title);
} catch (e) {
  console.error('dollar-patterns: title rendering crashed -> ' + e.message);
  process.exit(1);
}
const exp = 't: ' + ['$&', '$$', "$'", '$`', '$&'].map(v => JSON.stringify(v)).join(' ');
if (titles[0] !== exp) {
  console.error('dollar-patterns: got ' + JSON.stringify(titles[0])
              + ' want ' + JSON.stringify(exp));
  process.exit(1);
}
console.log('dollar-patterns ok: ' + titles[0]);
JS