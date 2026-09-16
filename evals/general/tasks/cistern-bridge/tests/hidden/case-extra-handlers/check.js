/* Hidden case: case-preserved event handlers on elements the upstream
 * regression tests do not touch (an <input> and a <button>, handlers ONFOCUS
 * and ONMOUSEOVER). Same defect: removal must be case-exact, or these survive.
 */
'use strict';

const { JSDOM, VirtualConsole } = require('/app/src/node_modules/jsdom');
const { window } = new JSDOM(
  '<!DOCTYPE html><html><body></body></html>',
  { runScripts: 'dangerously', virtualConsole: new VirtualConsole() }
);
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

{
  const input = document.createElement('input');
  input.setAttribute('type', 'text');
  input.setAttributeNS(null, 'ONFOCUS', 'alert(1)');
  const wrap = document.createElement('div');
  wrap.appendChild(input);
  check('ONFOCUS on <input>', DOMPurify.sanitize(wrap), /onfocus/i);
}

{
  const button = document.createElement('button');
  button.textContent = 'go';
  button.setAttributeNS(null, 'ONMOUSEOVER', 'alert(1)');
  const wrap = document.createElement('div');
  wrap.appendChild(button);
  check('ONMOUSEOVER on <button>', DOMPurify.sanitize(wrap), /onmouseover/i);
}

{
  // lowercase control on a third element: still removed after the fix
  const textarea = document.createElement('textarea');
  textarea.setAttribute('onchange', 'alert(1)');
  const wrap = document.createElement('div');
  wrap.appendChild(textarea);
  check('lowercase onchange control', DOMPurify.sanitize(wrap), /onchange/i);
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