"""Starter implementation of the HTML sanitizer (DEFECTIVE).

`sanitize_html(user_input)` is supposed to take raw user-supplied HTML and
return sanitized HTML per the contract in the task instructions. The current
implementation is a naive regex filter: it only drops known <script> blocks
and then strips *all* tags, which (a) destroys allowed formatting such as
<b>, <em>, <a> and (b) still lets through many attacks (event handlers,
javascript: URLs, iframes, SVG, mixed-case tags, malformed markup...).

Investigate its behaviour (run /app/check_sanitize.py), then replace this
module with a correct DOM-style sanitizer that follows the contract.
"""

import html
import re


def sanitize_html(user_input):
    out = re.sub(r"(?is)<script.*?</script>", "", user_input or "")
    out = re.sub(r"(?is)<[^>]*>", "", out)
    return html.escape(out, quote=True)