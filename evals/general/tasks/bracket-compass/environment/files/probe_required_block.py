#!/usr/bin/env python3
"""Exploratory probe for the required-block body check in the /app/src jinja
checkout.

Prints what the parser does with several required-block bodies.  Statement
content (a conditional, a nested block) should fail to compile with the clear
message "Required blocks can only contain comments or whitespace" but in this
checkout crashes with an internal AttributeError instead.  Exits non-zero if
any AttributeError is observed, so scripts can depend on the probe.
"""

import sys

from jinja2 import Environment, TemplateSyntaxError

CASES = [
    ("whitespace-only", "{% block x required %}   {% endblock %}"),
    ("comment-only", "{% block x required %}{# doc #}{% endblock %}"),
    ("if-statement", "{% block x required %}{% if true %}{% endif %}{% endblock %}"),
    ("nested-block", "{% block x required %}{% block y %}{% endblock %}{% endblock %}"),
    ("for-loop", "{% block x required %}{% for i in [1, 2] %}{% endfor %}{% endblock %}"),
    ("set-statement", "{% block x required %}{% set y = 1 %}{% endblock %}"),
]

bad = False
for name, src in CASES:
    try:
        Environment().from_string(src)
        print(f"compiled OK        <- {name}")
    except TemplateSyntaxError as e:
        print(f"TemplateSyntaxError <- {name}: {e}")
    except AttributeError as e:
        print(f"AttributeError      <- {name}: {e!r}")
        bad = True
    except Exception as e:  # unexpected: report loudly
        print(f"{type(e).__name__}    <- {name}: {e!r}")
        bad = True

sys.exit(1 if bad else 0)