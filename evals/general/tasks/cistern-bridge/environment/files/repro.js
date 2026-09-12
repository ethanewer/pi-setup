/* cistern-bridge repro: shows DOMPurify's failure to remove case-preserved
 * event-handler attributes when the input is an already-parsed DOM node.
 *
 * Run with:  node /app/repro.js        (from anywhere; paths are absolute)
 * Exits 0 when every attribute that must be removed is gone, 1 otherwise.
 */
'use strict';

function loadJsdom() {
  try {
    return require('jsdom');
  } catch (_) {
    return require('/app/src/node_modules/jsdom'); // when run from /app
  }
}

const { JSDOM } = loadJsdom();
const { window } = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
  runScripts: 'dangerously',
});
const DOMPurify = require('/app/src/dist/purify.cjs.js')(window);
const { document } = window;

const violations = [];

const check = (label, out, forbidden) => {
  if (forbidden.test(out)) {
    violations.push(`${label}: <<${out}>> still matches ${forbidden}`);
  } else {
    console.log(`ok: ${label} -> ${out}`);
  }
};

/* 1. uppercase event-handler attribute on a DOM-built node (no XML needed) */
{
  const img = document.createElement('img');
  img.setAttribute('src', 'x');
  img.setAttributeNS(null, 'ONERROR', 'alert(1)');
  const wrap = document.createElement('div');
  wrap.appendChild(img);
  check('uppercase ONERROR on node', DOMPurify.sanitize(wrap), /onerror/i);
}

/* 2. mixed-case ONCLICK on a node */
{
  const a = document.createElement('a');
  a.setAttribute('href', '#');
  a.setAttributeNS(null, 'ONCLICK', 'alert(1)');
  const wrap = document.createElement('div');
  wrap.appendChild(a);
  check('mixed-case ONCLICK on node', DOMPurify.sanitize(wrap), /onclick/i);
}

/* 3. uppercase HREF carrying a javascript: URL on a node */
{
  const a = document.createElement('a');
  a.setAttributeNS(null, 'HREF', 'javascript:alert(1)');
  a.textContent = 'x';
  const wrap = document.createElement('div');
  wrap.appendChild(a);
  check('uppercase HREF javascript: on node', DOMPurify.sanitize(wrap), /javascript:/i);
}

/* 4. lowercase control attribute is still removed */
{
  const img = document.createElement('img');
  img.setAttribute('src', 'x');
  img.setAttribute('onerror', 'alert(1)');
  const wrap = document.createElement('div');
  wrap.appendChild(img);
  check('lowercase onerror control', DOMPurify.sanitize(wrap), /onerror/i);
}

/* 5. string-input control: the same payload as a string is cleaned normally */
{
  const out = DOMPurify.sanitize('<img src=x ONERROR=alert(1)>');
  check('string-input ONERROR control', out, /onerror/i);
}

if (violations.length > 0) {
  console.error('VIOLATIONS:');
  for (const v of violations) {
    console.error('  - ' + v);
  }
  process.exit(1);
}
console.log('ALL CHECKS PASSED');
process.exit(0);