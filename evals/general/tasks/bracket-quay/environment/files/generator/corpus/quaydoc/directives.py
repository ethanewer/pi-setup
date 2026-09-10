"""Admonition (callout) directives and their rendering.

A source line of the form ``[note] ...`` opens an admonition block.  The
supported kinds map to short display labels; the parser collects the
following text lines into the callout body.
"""

from __future__ import annotations

import re

ADMONITION_TAGS = {
    "note": "Note",
    "tip": "Tip",
    "warn": "Warning",
    "danger": "Danger",
    "info": "Info",
}

ADMON_ORDER = ("note", "tip", "info", "warn", "danger")

_RE_ADMON = re.compile(r"^\[(note|tip|warn|danger|info)\][ \t]*(.*)$", re.I)


def parse_admonition_line(line):
    """Return ``(kind, rest)`` for an admonition line, else ``None``."""
    m = _RE_ADMON.match(line)
    if not m:
        return None
    return m.group(1).lower(), m.group(2)


def admonition_label(kind):
    """Display label for an admonition kind (unknown kinds pass through)."""
    return ADMONITION_TAGS.get(kind, kind.capitalize())


def admonition_css_class(kind):
    """CSS class used for the callout wrapper."""
    return "admonition admonition-" + kind


def is_admonition_kind(kind):
    return kind in ADMONITION_TAGS
