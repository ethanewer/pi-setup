/* Hidden case: several case-preserved attributes on ONE node, plus an
 * uppercase HREF=javascript: sibling, while safe attributes with case-preserved
 * names (ALT, DATA-TAG) must be kept. The upstream tests never combine
 * multiple case-preserved attributes on a single element.
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
const check = (label, cond, detail) => {
  if (cond) {
    console.log(`ok: ${label}`);
  } else {
    violations.push(`${label}: ${detail}`);
  }
};

let out = '';

{
  const img = document.createElement('img');
  img.setAttribute('src', 'x');
  img.setAttributeNS(null, 'ONERROR', 'alert(1)');
  img.setAttributeNS(null, 'ONLOAD', 'alert(2)');
  img.setAttributeNS(null, 'ALT', 'keep-me'); // safe: must survive
  img.setAttributeNS(null, 'DATA-TAG', 'keep'); // safe: must survive
  const wrap = document.createElement('div');
  wrap.appendChild(img);
  out = DOMPurify.sanitize(wrap);
}

check('ONERROR gone', !/onerror/i.test(out), `ONERROR survived: ${out}`);
check('ONLOAD gone', !/onload/i.test(out), `ONLOAD survived: ${out}`);
check('safe ALT kept', /ALT="keep-me"/.test(out), `ALT lost: ${out}`);
check('safe DATA-TAG kept', /DATA-TAG="keep"/.test(out), `DATA-TAG lost: ${out}`);

{
  const a = document.createElement('a');
  a.setAttributeNS(null, 'HREF', 'javascript:alert(1)');
  a.setAttributeNS(null, 'ONCLICK', 'alert(3)');
  a.textContent = 'x';
  const wrap = document.createElement('div');
  wrap.appendChild(a);
  out = DOMPurify.sanitize(wrap);
}

check('HREF=javascript: gone', !/javascript:/i.test(out), `HREF survived: ${out}`);
check('ONCLICK gone', !/onclick/i.test(out), `ONCLICK survived: ${out}`);
check('text content kept', /x/.test(out), `content lost: ${out}`);

if (violations.length > 0) {
  console.error('VIOLATIONS:');
  for (const v of violations) {
    console.error('  - ' + v);
  }
  process.exit(1);
}
console.log('ALL CHECKS PASSED');
process.exit(0);