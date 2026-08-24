# Item-003 (hard) — Harden a DOM sanitizer against a comprehensive
# adversarial XSS corpus, with exact output-format requirements

A legacy webapp still embeds user-generated HTML through `/app/sanitize.py`.
The current implementation is **deeply broken** (a naive regex filter). This
is a **hardened** assignment: you must model the attack surface, probe the
actual filter, and replace it with a correct, whitelist-based DOM sanitizer
that (1) preserves the app's legitimate behaviour exactly, and (2) neutralizes
a broad adversarial corpus — including the encoding/tokenization tricks that
real browsers accept.

## Contract for `sanitize_html(user_input)` in `/app/sanitize.py`

`sanitize_html(user_input: str) -> str` obeys exactly these rules:

**Allowed tags:** `b, i, strong, em, p, br, code, pre, span, ul, ol, li,
blockquote, a, h1, h2, h3` — output with lowercase names (`br` as `<br>`).

**Attributes:** only `a` may carry attributes, and only `href`. `href` is kept
only when its (already HTML-entity-decoded) value has a safe form: starts with
`http://`, `https://`, `mailto:`, `#`, or `/`. Anything else — in particular
`javascript:`, `vbscript:`, `data:` in any case or entity encoding — causes
the `href` to be dropped (text of the link is kept). All other attributes are
never emitted (`on*` handlers, `style`, `class`, `id`, `srcdoc`, …).

**Dangerous elements, dropped together with their whole contents (nested
too):** `script, iframe, style, svg, math, object, embed, applet, video,
audio, form, base, meta, link, noscript, template`.

**Everything else:** disallowed tags (e.g. `img`, `div`, `BODY`, `details`)
have their tags removed but **their text content kept and HTML-escaped**
(`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#x27;`). Comments and declarations are
dropped.

**Canonical serialization (important):** for a well-formed safe input the
output must be byte-identical to the input (`<p>Hello <b>world</b></p>` stays
exactly that string; `<a href="https://example.com/p">link</a>` stays exactly
that string — same quoting, same attribute order, text untouched beyond
escaping). Think of it as re-serializing the parsed tokens verbatim.

**Browser-tokenization awareness:** cases are matched case-insensitively and
the parser must follow how browsers tokenize HTML, including: unquoted
attribute values, `<tag/attr=value>` self-closing-looking forms,
`<svg><script>` nesting, entity-encoded attribute values
(`jav&#x61;script:` decoding to `javascript:`), control characters/whitespace
inside markup, and attributes on disallowed elements.

Use only the Python standard library (`html.parser.HTMLParser` is the natural
tool; `html.escape` for text).

## Evaluate

`/app/check_sanitize.py` runs a battery of safe/format/dangerous cases (16
dangerous payload classes) and reports `PASS`/`FAIL` per case; the verdict
goes to `/app/status.txt`. Iterate:

```bash
cd /app && python3 check_sanitize.py
```

## Also add pytest tests

Create `/app/tests/test_sanitizer.py` with `pytest` covering: safe text/format
preservation (including at least one exact round-trip), script, event
handlers (quoted and unquoted), javascript: and entity-encoded schemes,
iframe/SVG/math, self-closing `<img ... />`, and mixed-case tags. Then:

```bash
cd /app && python3 -m pytest /app/tests -q
```

## Success criteria

- `/app/sanitize.py` implements the contract; `/app/status.txt` says `PASS`.
- `/app/tests/test_sanitizer.py` exists and passes `pytest`.

The verifier re-runs the full battery against your module (including the exact
round-trip formatting checks) and requires the pytest suite to pass. Do not
modify `check_sanitize.py`.