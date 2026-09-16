// Reproduction for the bracket-beacon bug: function-form ADD_ATTR must not
// bypass URI-scheme validation. Exits 1 when the javascript: value survives.
// See /app/src and the repository README for the project itself.
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