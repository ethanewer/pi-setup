#!/usr/bin/env node
/* plinth-wicket bypass regression test.
 *
 * Documents the uncovered CSS mutation class: stock DOMPurify lets a
 * script/behavior-carrying style directive through, the hardened sanitizer in
 * /app/sanitize.js neutralizes it, and nothing ordinary is lost.
 *
 * Exits 0 only when the hardening is real.
 */
'use strict';

const createDOMPurify = require('/app/src/dist/purify.cjs');
const jsdom = require('/app/src/node_modules/jsdom');
const { sanitize } = require('/app/sanitize.js');

const { JSDOM } = jsdom;
const { window } = new JSDOM(
  '<!doctype html><html><body></body></html>',
  { runScripts: 'dangerously' }
);
const DOMPurify = createDOMPurify(window);

// A representative payload of the uncovered class (Expression() mutation).
const payload =
  '<div style="width:expression(alert(1));color:#c00">hi</div>' +
  '<img src=x onerror=alert(1)>';

const stock = DOMPurify.sanitize(payload);
const hardened = sanitize(payload);

let failures = 0;
const check = (label, cond) => {
  if (!cond) {
    failures++;
    console.error('FAIL: ' + label);
  } else {
    console.log('ok  : ' + label);
  }
};

// 1. The uncovered class: stock DOMPurify preserves the dangerous directive.
check(
  'stock DOMPurify leaks expression( in style (the uncovered class)',
  /expression\s*\(/.test(stock)
);
// 2. The hardened sanitizer neutralizes it.
check(
  'hardened sanitize removes expression( from style',
  !/expression\s*\(/.test(hardened)
);
// 3. Legitimate CSS survives the hardening.
check('hardened sanitize keeps legitimate CSS (color:#c00)', /color:#c00/.test(hardened));
// 4. Ordinary XSS is still stripped (real DOMPurify is being used).
check('hardened sanitize still strips onerror handlers', !/onerror/.test(hardened));
// 5. And a behavior: url() mutation is gone as well.
check(
  'hardened sanitize removes behavior: mutations',
  !/behavior\s*:/.test(
    sanitize('<a style="behavior:url(#default#AnchorClick);text-decoration:underline">x</a>')
  )
);

if (failures) {
  console.error(failures + ' bypass-test check(s) failed');
  process.exit(1);
}
console.log('bypass-test: all checks passed');
process.exit(0);
