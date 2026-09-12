/* Hidden case: the re-arm scenario from the bug report. Sanitizing a
 * DOM-node input must leave nothing that, once serialized back into an HTML
 * document, yields a live event-handler attribute. The upstream tests only
 * inspect the sanitized string; this one re-parses it and walks the resulting
 * tree looking for any on* attribute.
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

const liveHandlers = (root) => {
  const found = [];
  const walk = (el) => {
    for (const name of el.getAttributeNames()) {
      if (/^on/i.test(name)) {
        found.push(`${el.tagName}[${name}]`);
      }
    }
    for (const child of el.children) {
      walk(child);
    }
  };
  walk(root);
  return found;
};

{
  const div = document.createElement('div');
  div.setAttributeNS(null, 'ONMOUSEOVER', 'alert(1)');
  div.textContent = 'hover me';
  const wrap = document.createElement('div');
  wrap.appendChild(div);
  const out = DOMPurify.sanitize(wrap);

  const fresh = new JSDOM('<!DOCTYPE html><html><body></body></html>').window;
  fresh.document.body.innerHTML = out;
  const found = liveHandlers(fresh.document.body);
  if (found.length === 0) {
    console.log(`ok: reparse of <<${out}>> produces no live handler`);
  } else {
    violations.push(
      `reparse of <<${out}>> re-armed handlers: ${found.join(', ')}`
    );
  }
}

{
  // string-input control: an uppercase handler inside a string never survives
  const out = DOMPurify.sanitize('<div ONDBLCLICK="alert(1)">x</div>');
  const fresh = new JSDOM('<!DOCTYPE html><html><body></body></html>').window;
  fresh.document.body.innerHTML = out;
  const found = liveHandlers(fresh.document.body);
  if (found.length === 0) {
    console.log(`ok: string-input control reparse clean: <<${out}>>`);
  } else {
    violations.push(
      `string-input control re-armed handlers: ${found.join(', ')}`
    );
  }
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