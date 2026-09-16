// Hidden-case runner for bracket-beacon.
//
// Loads every tests/hidden/<case>/case.json, sanitizes the case's html input
// through the REBUILT dist/purify.cjs.js of the agent's checkout at /app/src,
// using the function-form ADD_ATTR callback declared by the case, and requires
// the exact expected output. Exits nonzero on any mismatch.
//
// Invoked as:  (cd /app/src && NODE_PATH=/app/src/node_modules node /tests/verify_hidden.js)
'use strict';

const fs = require('fs');
const path = require('path');
const { JSDOM, VirtualConsole } = require('jsdom');
const createDOMPurify = require('/app/src/dist/purify.cjs');

const virtualConsole = new VirtualConsole();
const { window } = new JSDOM(
  '<html><head></head><body></body></html>',
  { virtualConsole, runScripts: 'dangerously' }
);
const DOMPurify = createDOMPurify(window);

const hiddenDir = '/tests/hidden';
const cases = fs.readdirSync(hiddenDir)
  .filter((n) => fs.statSync(path.join(hiddenDir, n)).isDirectory())
  .sort();

let failed = 0;
for (const name of cases) {
  const p = path.join(hiddenDir, name, 'case.json');
  if (!fs.existsSync(p)) {
    console.log('FAIL ' + name + ': case.json missing');
    failed++;
    continue;
  }
  const c = JSON.parse(fs.readFileSync(p, 'utf8'));
  const allowed = Array.isArray(c.add_attr) ? c.add_attr : [c.add_attr];
  const out = DOMPurify.sanitize(c.html, {
    ADD_ATTR: (attr) => allowed.includes(attr),
  });
  if (out === c.expected) {
    console.log('ok ' + name);
  } else {
    console.log('FAIL ' + name + ': got ' + JSON.stringify(out) +
      ' expected ' + JSON.stringify(c.expected));
    failed++;
  }
}
console.log(failed === 0 ? 'HIDDEN-CASES PASS' : 'HIDDEN-CASES FAIL (' + failed + ')');
process.exit(failed === 0 ? 0 : 1);