"""Starter implementation of the HTML sanitizer (DEFECTIVE; hardened task).

`sanitize_html(user_input)` is supposed to take raw user-supplied HTML and
return sanitized HTML per the contract in the task instructions. The current
implementation is a naive regex filter: it drops <script> blocks and then
strips *all* tags. That destroys allowed formatting like <b>, <em>, <a>, and
still lets many attack classes through (event handlers, javascript: URLs,
iframes/SVG/math, entity-encoded schemes, mixed-case tags, malformed markup,
<svg><script>, self-closing variants, ...).

Probe it (run /app/check_sanitize.py), then replace this module with a
correct DOM-style whitelist sanitizer implementing the contract exactly.
"""

import html
import re


def sanitize_html(user_input):
    out = re.sub(r"(?is)<script.*?</script>", "", user_input or "")
    out = re.sub(r"(?is)<[^>]*>", "", out)
    return html.escape(out, quote=True)