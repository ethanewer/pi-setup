// Oracle reproduction for fender-hull. The deliverable contract:
//   - loads the DOMPurify library from $DOMPURIFY_MODULE (default
//     /app/src/dist/purify.cjs);
//   - reproduces the user-visible symptom (in-place sanitize of a live form
//     subtree whose document-owner lookup is intercepted aborts and leaves an
//     armed on* handler attached to a surviving descendant);
//   - exits 0 when the symptom is absent (handler stripped, whether or not
//     the call fails closed), nonzero when the armed handler survives.
const { JSDOM, VirtualConsole } = require('jsdom');

const modulePath = process.env.DOMPURIFY_MODULE || '/app/src/dist/purify.cjs';
const createDOMPurify = require(modulePath);

const { window } = new JSDOM(
  '<html><head></head><body></body></html>',
  { virtualConsole: new VirtualConsole(), runScripts: 'dangerously' }
);
const DOMPurify = createDOMPurify(window);

const doc = window.document;
const root = doc.createElement('form');
const img = doc.createElement('img');
img.setAttribute('onerror', 'alert(1)');
root.appendChild(img);
doc.body.appendChild(root);

// Reproduce the shadow faithfully: an own accessor intercepting the
// document-owner lookup on the root, exactly what [LegacyOverrideBuiltIns]
// surfaces on HTMLFormElement in clobbering engines.
const fake = doc.createElement('input');
Object.defineProperty(root, 'ownerDocument', {
  get() {
    return fake;
  },
  configurable: true,
});

try {
  DOMPurify.sanitize(root, { IN_PLACE: true });
  console.log('THREW: no');
} catch (e) {
  console.log('THREW:', e.constructor.name, '-', e.message);
}

const survived = img.getAttribute('onerror') !== null;
console.log('onerror survived:', survived);
process.exit(survived ? 1 : 0);