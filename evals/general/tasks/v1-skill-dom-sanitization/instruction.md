# DOM sanitization: neutralize XSS payloads in HTML

`/app/payloads.html` contains five lines, each one an HTML snippet carrying a
possible cross-site-scripting (XSS) attack. You must write an HTML sanitizer
that makes the snippets safe while preserving benign markup.

## Task

Write a Python 3 module `/app/sanitize.py` defining:

```python
def sanitize(html: str) -> str:
    ...
```

Your `sanitize` must apply **all three** of the following transformations,
**case-insensitively** (handle `SCRIPT`, `OnErRoR=`, etc. too):

1. **Remove script elements entirely** — any `<script ...> ... </script>`
   block (including its content) is deleted from the output.
2. **Strip event-handler attributes** — remove every attribute whose name
   starts with `on` (e.g. `onclick`, `onerror`, `onload`), including the `=`
   and its quoted or unquoted value, up to the next whitespace, `>`, or quote.
3. **Neutralize `javascript:` URLs** — inside `href`/`src` attribute values,
   remove the `javascript:` prefix (and only that prefix; keep the rest of the
   value).

Then write `/app/sanitized.txt`: apply `sanitize` to **each** line of
`/app/payloads.html` in order, and write the results one per line (an emptied
line stays as an empty line).

## Reference behavior (check your output against this)

For the given input lines:

```
<script>alert(1)</script>
<img src=x onerror=alert(1)>
<a href="javascript:alert(1)">x</a>
<div onclick=evil()>hi</div>
<script src="javascript:evil.js"></script>
```

the sanitized output should be (empty lines are genuinely empty):

```

<img src=x>
<a href="alert(1)">x</a>
<div>hi</div>

```

The verifier imports your `sanitize` function, runs it on all five payloads,
and checks that no dangerous artifact (`<script`, `onclick=`, `onerror=`,
`javascript:`) survives in any of the outputs — you may also run it yourself
to confirm.