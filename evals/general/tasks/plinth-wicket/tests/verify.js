#!/usr/bin/env node
/* plinth-wicket verifier helper.
 *
 * Runs the hardened /app/sanitize.js against every hidden payload in
 * /tests/hidden and asserts:
 *   - the dangerous CSS directives are absent from the output,
 *   - the legitimate CSS markers are still present,
 *   - ordinary XSS is still stripped (proving real DOMPurify is in the loop),
 *   - the module actually binds to the clone's DOMPurify (not a hand-rolled
 *     HTML parser that ignores the upstream tree).
 *
 * Writes detailed failures to stdout. Exit 0 only when every hidden case and
 * the source-binding check pass.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const HIDDEN = '/tests/hidden';

function fail(msg) {
  console.error('FAIL: ' + msg);
  process.exitCode = 1;
}

function arrayHasAny(hay, needles) {
  return needles.some((n) => hay.includes(n));
}

let ok = true;

// 1. The hardened module must genuinely bind to the clone's DOMPurify build,
//    otherwise the task could be passed without ever touching the upstream
//    library (a fresh self-contained script would be a different, non-upstream
//    deliverable).
const srcPath = '/app/sanitize.js';
if (!fs.existsSync(srcPath)) {
  fail('/app/sanitize.js missing');
  process.exit(1);
}
const sanitizeSrc = fs.readFileSync(srcPath, 'utf8');
if (!/require\s*\([^)]*(?:purify\.cjs|dompurify)|from\s+['"][^'"]*(?:purify\.cjs|dompurify)/i.test(sanitizeSrc)) {
  fail('/app/sanitize.js does not load the real DOMPurify build (purify.cjs/dompurify) from the clone');
  ok = false;
}

let sanitize;
try {
  sanitize = require('/app/sanitize.js').sanitize;
} catch (e) {
  fail('/app/sanitize.js failed to load: ' + e.message);
  process.exit(1);
}
if (typeof sanitize !== 'function') {
  fail('/app/sanitize.js does not export a sanitize() function');
  ok = false;
}

// 1b. STOCK-PARITY PROBE: the module must be the clone's DOMPurify, not a
// hand-rolled lookalike. For payloads where ONLY ordinary DOMPurify
// sanitization should apply (no style-attribute CSS class involved), the
// output must be byte-identical to the clone's own stock DOMPurify output.
// Any legitimate hardening that lets non-style behavior drift would break
// the task's own "ordinary stripping still applies" contract, so requiring
// equality here cannot break a correct solution. A jsdom-based impostor
// (dead `require` of purify.cjs plus its own parser) diverges on every probe
// below: DOMPurify drops srcdoc, removes <object>/<template>, keeps
// <svg><a>/<details open> canonical output, and never emits the
// <html><head>... wrapper a raw dom.serialize() adds.
let stock = null;
try {
  const jsdom = require('/app/src/node_modules/jsdom');
  const createRef = require('/app/src/dist/purify.cjs');
  const refWin = new jsdom.JSDOM('<!doctype html><html><body></body></html>').window;
  stock = createRef(refWin).sanitize;
} catch (e) {
  // clone missing would fail earlier; treat as fatal
  fail('could not build reference DOMPurify for the parity probe: ' + e.message);
  ok = false;
}
const PROBES = [
  '<p onclick="x()">hi</p>',
  '<iframe src="x" srcdoc="<script>alert(1)</script>"></iframe>',
  '<svg><a xlink:href="javascript:alert(1)" href="/x">t</a></svg>',
  '<object data="x"><param name="a" value="b"></object>',
  '<template><p>t</p></template>',
  '<details open><summary>s</summary></details>',
  '<a data-uid="1" aria-hidden="true" href="/ok">go</a>',
  '<img srcset="a 1x, b 2x" src="s">',
  '<style>p{color:red}</style><p>t</p>',
  '<p style="mask:url(#m)">x</p>',
  '<p style="color:red">x</p>'
];
if (stock) {
  for (const p of PROBES) {
    const expected = stock(p);
    let got = null;
    try { got = sanitize(p); } catch (e) {}
    if (got !== expected) {
      fail('parity probe diverges from stock DOMPurify for ' + JSON.stringify(p.slice(0, 60)) +
        ' -> expected ' + JSON.stringify(expected) + ' got ' + JSON.stringify(got) +
        ' (the module is not really the clone DOMPurify under the hood)');
      ok = false;
    }
  }
  if (ok) console.log('parity probe: ' + PROBES.length + ' non-style payloads byte-identical to the clone\'s DOMPurify');
}


// 2. Every hidden case.
const cases = fs
  .readdirSync(HIDDEN, { withFileTypes: true })
  .filter((e) => e.isDirectory())
  .map((e) => e.name)
  .sort();

if (cases.length < 2) {
  fail('expected at least 2 hidden cases, found ' + cases.length);
  ok = false;
}

for (const c of cases) {
  const dir = path.join(HIDDEN, c);
  const payloadFile = path.join(dir, 'payload.html');
  const specFile = path.join(dir, 'spec.json');
  if (!fs.existsSync(payloadFile) || !fs.existsSync(specFile)) {
    fail(c + ': missing payload.html or spec.json');
    ok = false;
    continue;
  }
  const payload = fs.readFileSync(payloadFile, 'utf8');
  const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));

  let out = '';
  try {
    out = sanitize(payload);
  } catch (e) {
    fail(c + ': sanitize() threw: ' + e.message);
    ok = false;
    continue;
  }

  for (const needle of spec.must_not || []) {
    if (out.toLowerCase().includes(needle.toLowerCase())) {
      fail(c + ': output still contains prohibited directive "' + needle + '" -> ' + JSON.stringify(out));
      ok = false;
    }
  }
  for (const needle of spec.must_contain || []) {
    if (!out.includes(needle)) {
      fail(c + ': output lost legitimate marker "' + needle + '" -> ' + JSON.stringify(out));
      ok = false;
    }
  }
  console.log('hidden[' + c + ']: ' + JSON.stringify(out));
}

if (!ok) {
  console.error('verifier: one or more hidden/source-binding checks failed');
  process.exit(1);
}
console.log('verifier: all hidden cases sanitised correctly');
process.exit(0);
