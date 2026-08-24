# Item-003 (medium) — Replace a broken HTML sanitizer with a robust
# DOM-style, whitelist-based sanitizer

Your webapp embeds user-generated HTML. The current sanitizer,
`/app/sanitize.py`, is **broken**: run it and you'll see it strips *all* tags
(so `<b>` and links are destroyed) while still letting dangerous payloads
through in some cases. Your job is to **model the attacks, probe the actual
filter, and rebuild it** so that it removes dangerous behavior while
preserving the allowed behavior.

## Contract for `sanitize_html(user_input)` in `/app/sanitize.py`

`sanitize_html(user_input: str) -> str` returns sanitized HTML that obeys
exactly these rules:

**Allowed tags (whitelist):** `b, i, strong, em, p, br, code, pre, span, ul,
ol, li, blockquote, a, h1, h2, h3`.

- `br` renders as `<br>`.
- Among the allowed tags, only `a` may carry an attribute, and only
  `href`. The `href` attribute is kept **only** if its scheme is safe:
  `http://`, `https://`, `mailto:`, an absolute `#fragment`, or a relative
  path starting with `/`. Otherwise the `href` is dropped (the `<a>` tag and
  its text remain). Reject in particular `javascript:`, `vbscript:` and
  `data:` URLs in any casing or entity-encoded form.
- All other attributes — including every event handler (`on*`), `style`,
  `class`, `id`, `srcdoc` — are removed, never emitted.

**Dangerous elements (dropped together with their entire contents):**
`script, iframe, style, svg, math, object, embed, applet, video, audio,
form, base, meta, link, noscript, template`. Their inner text must not
survive either.

**Everything else:**

- Any tag not in the whitelist (e.g. `<img>`, `<div>`, `<BODY>`) is removed,
  but its **text content is kept** and HTML-escaped.
- Text is HTML-escaped with the standard five entities (`&amp;`, `&lt;`,
  `&gt;`, `&quot;`, `&#x27;`).
- Comments and markup declarations are dropped.
- Tags are matched case-insensitively (e.g. `<SCRIPT SRC=...>` is treated as
  `script`), matching browser behaviour for how the input can be tokenized
  (attributes without quotes, `/>` self-closing forms, entity-encoded
  attribute values).

You may use only the Python standard library (e.g. `html.parser.HTMLParser`).

## Evaluate

`/app/check_sanitize.py` imports your module and checks 6 safe inputs (their
allowed markup/text must survive) and 10 dangerous inputs (no forbidden token
may survive — including `onerror=`, `javascript:`, `iframe`, `srcdoc`,
`svg`). Run it and iterate:

```bash
cd /app && python3 check_sanitize.py
```

It prints one `PASS`/`FAIL` per case and writes the verdict to
`/app/status.txt`.

## Also add pytest tests

Create `/app/tests/test_sanitizer.py` — a `pytest` suite covering
representative safe-preservation cases and the dangerous payload classes
(script, event handlers, javascript: URLs, iframes/SVG, entity-encoded
schemes, mixed case). Run:

```bash
cd /app && python3 -m pytest /app/tests -q
```

Everything must pass.

## Success criteria

- `/app/sanitize.py` implements the contract; `/app/status.txt` says `PASS`.
- `/app/tests/test_sanitizer.py` exists and passes `pytest`.

The verifier independently re-runs the same safe/dangerous battery against
your module and also requires the pytest suite to exist and pass. Do not
modify `check_sanitize.py` or its expected file paths.