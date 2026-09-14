// Hidden case B: non-form root, nested table payload, javascript: href vector,
// <object>-shaped clobber target.
const { JSDOM, VirtualConsole } = require('jsdom');
const createDOMPurify = require(process.env.DOMPURIFY_MODULE);
const { window } = new JSDOM('<html><head></head><body></body></html>', { virtualConsole: new VirtualConsole(), runScripts: 'dangerously' });
const DOMPurify = createDOMPurify(window);
const doc = window.document;
const root = doc.createElement('div');
root.setAttribute('data-keep', 'yes');
const table = doc.createElement('table');
const tr = doc.createElement('tr');
const td = doc.createElement('td');
const img = doc.createElement('img');
img.setAttribute('onerror', 'alert(9)');
const a = doc.createElement('a');
a.setAttribute('href', 'javascript:alert(9)');
a.textContent = 'click';
const akept = doc.createElement('a');
akept.setAttribute('href', 'https://example.com/');
akept.textContent = 'safe';
td.appendChild(img); td.appendChild(a); td.appendChild(akept);
tr.appendChild(td); table.appendChild(tr); root.appendChild(table);
doc.body.appendChild(root);
const fake = doc.createElement('object');
Object.defineProperty(root, 'ownerDocument', { get() { return fake; }, configurable: true });
let threw = false;
try { DOMPurify.sanitize(root, { IN_PLACE: true }); }
catch (e) { threw = true; console.log('THREW', e.message); }
const checks = [];
checks.push(['no-throw', !threw]);
checks.push(['onerror-stripped', img.getAttribute('onerror') === null]);
checks.push(['js-href-stripped', a.getAttribute('href') === null]);
checks.push(['https-href-kept', akept.getAttribute('href') === 'https://example.com/']);
checks.push(['table-intact', table === tr.parentElement && tr === td.parentElement]);
checks.push(['data-keep', root.getAttribute('data-keep') === 'yes']);
let bad = 0;
for (const [name, ok] of checks) { console.log((ok ? 'HIDDEN-OK ' : 'HIDDEN-FAIL ') + name); if (!ok) bad++; }
process.exit(bad ? 1 : 0);
