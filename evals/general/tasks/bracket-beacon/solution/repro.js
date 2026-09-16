// Oracle reproduction: exits 1 while the dangerous javascript: value
// survives a function-form ADD_ATTR sanitization.
const { JSDOM, VirtualConsole } = require('jsdom');
const createDOMPurify = require('/app/src/dist/purify.cjs');
const virtualConsole = new VirtualConsole();
const { window } = new JSDOM('<html><head></head><body></body></html>', {
  virtualConsole,
  runScripts: 'dangerously',
});
const DOMPurify = createDOMPurify(window);
const out = DOMPurify.sanitize('<a href="javascript:alert(1)">x</a>', {
  ADD_ATTR: (attr) => attr === 'href',
});
console.log('OUT:', JSON.stringify(out));
if (out.indexOf('javascript:') !== -1) {
  console.log('RESULT: FAIL');
  process.exit(1);
}
console.log('RESULT: PASS');