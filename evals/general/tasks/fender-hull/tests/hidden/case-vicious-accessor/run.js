// Hidden case C: vicious ownerDocument accessor — getter THROWS when the page
// reads root.ownerDocument directly. The fix must never invoke the own
// accessor: sanitize must complete, strip the armed handler, and leave the
// page's poisoned property in place for the caller to observe.
const { JSDOM, VirtualConsole } = require('jsdom');
const createDOMPurify = require(process.env.DOMPURIFY_MODULE);
const { window } = new JSDOM('<html><head></head><body></body></html>', { virtualConsole: new VirtualConsole(), runScripts: 'dangerously' });
const DOMPurify = createDOMPurify(window);
const doc = window.document;
const root = doc.createElement('form');
root.setAttribute('data-case', 'c');
const img = doc.createElement('img');
img.setAttribute('onerror', 'alert(5)');
const p = doc.createElement('p');
p.textContent = 'keep text';
root.appendChild(p);
root.appendChild(img);
doc.body.appendChild(root);
Object.defineProperty(root, 'ownerDocument', {
  get() { throw new Error('CLOBBERED-OWNER-ERROR'); },
  configurable: true,
});
let threw = null;
try { DOMPurify.sanitize(root, { IN_PLACE: true }); }
catch (e) { threw = e.message; }
let directRead = 'n/a';
try { directRead = String(root.ownerDocument); } catch (e) { directRead = 'THREW:' + e.message; }
const checks = [];
checks.push(['no-throw', threw === null]);
checks.push(['handler-stripped', img.getAttribute('onerror') === null]);
checks.push(['text-kept', p.textContent === 'keep text']);
checks.push(['subtree-intact', p.parentElement === root && img.parentElement === root]);
checks.push(['clobber-untouched', directRead === 'THREW:CLOBBERED-OWNER-ERROR']);
let bad = 0;
for (const [name, ok] of checks) { console.log((ok ? 'HIDDEN-OK ' : 'HIDDEN-FAIL ') + name); if (!ok) bad++; }
process.exit(bad ? 1 : 0);