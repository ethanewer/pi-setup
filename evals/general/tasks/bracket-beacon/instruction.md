# DOMPurify: URI filtering is bypassed by the function form of ADD_ATTR

## The environment

`/app/src` is a checkout of the real DOMPurify HTML-sanitizer repository
(cure53/DOMPurify) at a fixed revision, complete and self-contained. Its npm
dependencies are already installed (jsdom 29.1.x, jquery 3.7.1, qunit and the
full build toolchain), so the project builds and its tests run with no network.
There is no network in this environment: do not try to install, fetch or clone
anything.

The project compiles its TypeScript sources into distributable artifacts in
`dist/` with `npm run build` (see `package.json`); the committed `dist/` is
treated as build output and is regenerated from source. `npm run build` has
been run in this image already, and everything it needs is cached.

## The bug

This checkout fails to apply its URI-scheme whitelist to attribute *values*
when the caller permits additional attribute names through DOMPurify's
function-form `ADD_ATTR` option. Concretely: an `<a>` whose `href` carries a
`javascript:` URL comes back out of `sanitize()` with that dangerous value
intact, as long as the permission comes from a callback function rather than a
plain array.

Reproduce it with this script (jsdom is installed; `dist/purify.cjs.js` is the
build of the revision you have):

```js
const { JSDOM, VirtualConsole } = require('jsdom');
const createDOMPurify = require('/app/src/dist/purify.cjs');
const { window } = new JSDOM('<html><head></head><body></body></html>',
  { virtualConsole: new VirtualConsole(), runScripts: 'dangerously' });
const DOMPurify = createDOMPurify(window);
const out = DOMPurify.sanitize('<a href="javascript:alert(1)">x</a>',
  { ADD_ATTR: (attr) => attr === 'href' });
console.log(out);
if (out.indexOf('javascript:') !== -1) process.exit(1);
```

On the unmodified checkout this prints `<a href="javascript:alert(1)">x</a>`
and exits 1: the `javascript:` URL rides through unharmed. The identical input
under the array form (`ADD_ATTR: ['href']`) or under the built-in defaults is
cleaned correctly, so the bypass is specific to the function form of
`ADD_ATTR`. A working copy of this script is at `/app/repro.js`; a safe
`https://` href passes untouched in all three configurations.

## What you must deliver

Repair the security behaviour of `/app/src` so that, after your change and a
fresh `npm run build`:

1. The reproduction above exits 0 — the `javascript:` value is stripped from
   the output.
2. Safe URIs in the same callback-permitted position are preserved verbatim:
   `sanitize('<a href="https://example.com">x</a>', { ADD_ATTR: (attr) => attr === 'href' })`
   must return `<a href="https://example.com">x</a>`.
3. The filtering generalises: any URI-valued attribute the callback permits
   (for example `src`, `formaction`, `cite`, `poster`) is checked against the
   same URI whitelist as attributes permitted by the built-in configuration,
   while non-URI attributes the callback permits keep working.
4. The project's own test suite stays green: from `/app/src`, run its jsdom
   suite with `node test/jsdom-node-runner` (the `--dot` flag and the
   `npm run test:jsdom` shortcut hide the details; plain output ends with the
   plan line `1..980` and every case ok). The fix must not change, skip,
   weaken or delete any project test.

The verifier rebuilds `dist/` from your edited source before grading, so make
the fix in the source, not only in the shipped build output.

Work directly in the working tree of `/app/src`. Do not commit: the verifier
requires the checkout to remain at its pinned revision, with the working-tree
diff limited to your source fix and the regenerated build outputs under
`dist/`.

## Output contract

A corrected source tree at `/app/src`: the dangerous URI scheme is stripped
from callback-permitted attribute values, safe URIs survive, and the project's
own suite still passes every case.