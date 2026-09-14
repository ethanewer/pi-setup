// Hidden case A: deeper subtree, onmouseover, <textarea>-shaped clobber target,
// natural <input name="ownerDocument"> child present, benign attrs preserved,
// IN_PLACE returns the live root object.
const { JSDOM, VirtualConsole } = require('jsdom');
const createDOMPurify = require(process.env.DOMPURIFY_MODULE);
const { window } = new JSDOM('<html><head></head><body></body></html>', { virtualConsole: new VirtualConsole(), runScripts: 'dangerously' });
const DOMPurify = createDOMPurify(window);
const doc = window.document;
const root = doc.createElement('form');
root.setAttribute('id', 'keep-root-id');
root.setAttribute('class', 'reachable');
const input = doc.createElement('input');
input.setAttribute('name', 'ownerDocument');
root.appendChild(input);
const section = doc.createElement('section');
const p = doc.createElement('p');
const img = doc.createElement('img');
img.setAttribute('onmouseover', 'alert(7)');
img.setAttribute('alt', 'alttext');
p.appendChild(img); section.appendChild(p); root.appendChild(section);
doc.body.appendChild(root);
const fake = doc.createElement('textarea');
Object.defineProperty(root, 'ownerDocument', { get() { return fake; }, configurable: true });
let returned = null, threw = false;
try { returned = DOMPurify.sanitize(root, { IN_PLACE: true }); }
catch (e) { threw = true; console.log('THREW', e.message); }
const checks = [];
checks.push(['no-throw', !threw]);
checks.push(['returned-root', returned === root]);
checks.push(['handler-stripped', img.getAttribute('onmouseover') === null]);
checks.push(['alt-kept', img.getAttribute('alt') === 'alttext']);
checks.push(['deep-intact', section === p.parentElement && p === img.parentElement]);
checks.push(['root-id-kept', root.getAttribute('id') === 'keep-root-id']);
let bad = 0;
for (const [name, ok] of checks) { console.log((ok ? 'HIDDEN-OK ' : 'HIDDEN-FAIL ') + name); if (!ok) bad++; }
process.exit(bad ? 1 : 0);
