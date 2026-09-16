# Plinth Wicket — harden the sanitizer against a CSS mutation class

## Background

The Embeddable Content Service (ECS) renders untrusted HTML fragments. Every
fragment is sanitized with **DOMPurify**, which you will find already installed
as the **real upstream release 3.4.15**:

- source: `/app/src`
- built CommonJS distributable: `/app/src/dist/purify.cjs`
- full node toolchain (jsdom, qunit, rollup, …): `/app/src/node_modules`

The project's own regression suite is complete and green right now: run it with

```bash
cd /app/src && node test/jsdom-node-runner
```

It exercises 1227 sanitization cases (plan line `1..1227`). That suite is the
project's contract — you must keep every one of those tests passing in the
state in which it exists today in `/app/src/test`.

## The security gap you must close

A customer reported that embedded fragments can still smuggle **script or
legacy behavior through `style` attributes**. When a fragment like

```html
<div style="width:expression(alert(1));color:#c00">hi</div>
```

is passed to the stock sanitizer's default `sanitize()`, the dangerous
directive survives verbatim. The project's own test suite documents this class
— several of its fixtures assert that a `style` attribute value (including
`behavior:url(...)` and `url(javascript:alert(...))`) is **preserved** — which
is to say the suite locks the vulnerable behaviour in rather than closing it.
Your job is to close it in a new abstraction, without breaking or weakening any
of those 1227 tests.

Concretely, the class of CSS you must neutralize, wherever it appears inside a
`style` value on any element, is the family of directives that can carry script
or legacy behavior:

- `expression(...)` (IE/Firefox legacy CSS expression evaluation)
- `behavior:` / `-moz-binding:` / `-ms-binding:` (behavior loading)
- `url(...)` whose URL names a script-capable scheme such as `javascript:`,
  `vbscript:`, `livescript:`, or `data:` — including when the scheme is
  obfuscated with mixed case or embedded whitespace/control characters

while **preserving** legitimate styling: colors, lengths, and in particular
fragment references like `url(#m)` (used by SVG masks/filters) and plain CSS
declarations. A blunt "drop every `style` attribute" or "drop every `url(`" is
not an acceptable fix.

## Deliverables (create both under `/app`)

### 1. `/app/sanitize.js`

A hardened sanitizer **built on the real DOMPurify from `/app/src`** — this is
required, not optional: the module must load `dist/purify.cjs` from the clone
(or otherwise bind to that exact DOMPurify instance), and its output must still
strip the ordinary XSS set that DOMPurify strips (event handlers, `<script>`,
`<iframe>`, …). It must not be a hand-written HTML parser that ignores the
library.

Module contract:

```js
module.exports = {
  sanitize(htmlString) -> string
};
```

`sanitize(html)` returns a string of cleaned output in which every `style`
attribute value has had the script/behavior CSS class above neutralized, all
legitimate CSS (including `url(#...)` fragment references) survives, and the
ordinary DOMPurify sanitization (tags, attributes, handlers) still applies.

You may use the DOMPurify extension mechanisms (configuration, hooks) to
realise this. Do not modify the library's own source under `/app/src` (its
`src/`, `dist/`, or `test/`) — ship your hardening as the `/app/sanitize.js`
module. `/app/src` must remain byte-for-byte at the upstream 3.4.15 state the
image verified at build time.

### 2. `/app/bypass-test.js`

A runnable Node script (executed with `node /app/bypass-test.js`) that is the
"counter-example regression test" for the uncovered class. It must:

- demonstrate, on at least one self-contained payload of the CSS class above,
  that **stock** `DOMPurify.sanitize` (the default config from the clone) leaves
  the dangerous directive in its output;
- demonstrate that `/app/sanitize.js` neutralizes it;
- `process.exit(0)` exactly when both hold, and non-zero otherwise.

It must not read anything under `/tests`.

## Acceptance criteria

The verifier will:

1. run the project's own suite (`node test/jsdom-node-runner`) in `/app/src`
   and require all 1227 cases pass — proving no existing test was skipped,
   removed, weakened, or broken, and that `/app/src` was not mutated;
2. run `/app/bypass-test.js` and require exit 0;
3. run `/app/sanitize.js` against hidden payloads spanning the CSS class above
   (different directives, different obfuscations, different legitimate CSS that
   must survive) and require each hidden payload to be sanitised: the dangerous
   directive gone, the legitimate styling intact, and ordinary XSS still
   stripped.

Do not hardcode the hidden inputs into your module; your solution must
generalise to any payload of the class.

The `/app/src` clone must stay pristine. If you need to test the suite, run it
as shipped; do not edit or delete any file under `/app/src`.
