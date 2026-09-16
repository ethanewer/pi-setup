"""Front matter parsing and validation.

Every quaydoc source file may start with a ``---`` fenced block of
``key: value`` lines describing the page::

    ---
    title: Building a site
    order: 40
    date: 2025-01-02
    tags: [guide, build]
    draft: false
    ---

Values are typed loosely (bool/int where obvious), ``tags`` is always
normalised to a list, and unknown keys are kept in the mapping so templates
and plugins can read them.
"""

from __future__ import annotations

import re
from datetime import date, datetime, timezone

from quaydoc.errors import ParseError

FRONTMATTER_RE = re.compile(r"\A---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)", re.S)
KEYLINE_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$")
DATE_KEYS = {"date", "updated", "published"}
LIST_KEYS = {"tags", "authors", "keywords"}


def _parse_scalar(raw):
    value = raw.strip()
    if not value:
        return ""
    low = value.lower()
    if low == "true":
        return True
    if low == "false":
        return False
    if low in ("null", "none", "~"):
        return None
    if re.fullmatch(r"[+-]?\d+", value):
        return int(value)
    if re.fullmatch(r"[+-]?\d+\.\d+", value):
        return float(value)
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1]
        return [
            item.strip().strip("\"'") for item in inner.split(",")
            if item.strip()
        ]
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1]
    return value


def parse_frontmatter(text):
    """Split ``text`` into a ``(frontmatter_dict, body)`` pair.

    The body is the remainder of the document with the closing fence removed.
    A document without front matter yields ``({}, text)``.
    """
    match = FRONTMATTER_RE.match(text)
    if not match:
        return {}, text
    block, body = match.group(1), text[match.end():]
    data = {}
    for lineno, line in enumerate(block.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        km = KEYLINE_RE.match(line)
        if not km:
            raise ParseError("<frontmatter>", lineno,
                             f"expected 'key: value', got {line!r}")
        key, raw = km.group(1), km.group(2)
        if key in DATE_KEYS:
            data[key] = _parse_date(raw)
        elif key in LIST_KEYS or str(raw).strip().startswith("["):
            value = _parse_scalar(raw)
            data[key] = value if isinstance(value, list) else [value]
        else:
            data[key] = _parse_scalar(raw)
    return data, body


def _parse_date(raw):
    value = raw.strip().strip("\"'")
    try:
        return date.fromisoformat(value.split("T")[0])
    except ValueError:
        try:
            return datetime.fromisoformat(value).date()
        except ValueError:
            return value


KNOWN_KEYS = {
    "title", "description", "order", "date", "updated", "published",
    "tags", "authors", "keywords", "draft", "layout", "nav_title",
    "toc", "permalink", "template",
}


def validate_frontmatter(data, source):
    """Return a list of warning strings for unusual front matter keys."""
    warnings = []
    for key in data:
        if key not in KNOWN_KEYS:
            warnings.append(f"{source}: unknown front matter key {key!r}")
    order = data.get("order")
    if order is not None and not isinstance(order, int):
        warnings.append(f"{source}: 'order' should be an integer")
    return warnings


# ---------------------------------------------------------------------------
# date normalisation (shared by sitemap / feed / page metadata)
# ---------------------------------------------------------------------------


def parse_date(value):
    """Normalise a date value to ``datetime.date`` (None when unparseable)."""
    if isinstance(value, date):
        return value
    if isinstance(value, datetime):
        return value.date()
    if not isinstance(value, str):
        return None
    text = value.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        try:
            return date.fromisoformat(text)
        except ValueError:
            return None
    m = re.fullmatch(
        r"(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?"
        r"(Z|[+-]\d{2}:?\d{2})?", text)
    if m:
        return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    return None


def iso_date(value):
    """ISO-8601 string for a date value, or ``None``."""
    parsed = parse_date(value)
    return parsed.isoformat() if parsed else None


def rfc3339(value):
    """RFC-3339 UTC string (Atom feeds); ``None`` when unparseable."""
    parsed = parse_date(value)
    if parsed is None:
        return None
    return datetime(parsed.year, parsed.month, parsed.day,
                    tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")


def human(value):
    """Friendly ``YYYY-MM-DD`` rendering (empty when unparseable)."""
    parsed = parse_date(value)
    return parsed.isoformat() if parsed else ""


def sortable(value):
    """Tuple ordering key for page dates (never raises)."""
    parsed = parse_date(value)
    if parsed is None:
        return (9999, 12, 31)
    return (parsed.year, parsed.month, parsed.day)
