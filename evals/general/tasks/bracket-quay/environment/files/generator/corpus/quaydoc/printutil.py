"""Small terminal reporting helpers.

Colors are only emitted when stdout is a TTY and the ``NO_COLOR``
environment variable is unset, so piped output stays clean.
"""

from __future__ import annotations

import os
import sys

_COLORS = {"red": "31", "green": "32", "yellow": "33", "bold": "1"}


def _use_color():
    return (hasattr(sys.stdout, "isatty") and sys.stdout.isatty()
            and not os.environ.get("NO_COLOR"))


def _paint(text, color):
    if _use_color() and color in _COLORS:
        return f"\x1b[{_COLORS[color]}m{text}\x1b[0m"
    return text


def ok(message):
    print(_paint("ok: ", "green") + message)


def fail(message):
    print(_paint("error: ", "red") + message)


def warn(message):
    print(_paint("warning: ", "yellow") + message)


def info(message):
    print(message)


def section(message):
    print("")
    print(_paint(message, "bold"))
    print("-" * 40)


def format_table(rows, headers=None, align=None, cell_limit=48,
                 border=True):
    """Render ``rows`` as a fixed-width text table.

    ``headers`` optionally prepends a header row; ``align`` maps column
    indexes to ``"l"``/``"r"`` (default left).  Cells longer than
    ``cell_limit`` characters are truncated at a word boundary with an
    ellipsis.  Returns the display string (no trailing newline).
    """
    if not rows and not headers:
        return ""
    body = [headers] + list(rows) if headers else list(rows)
    cols = max(len(row) for row in body)
    widths = [0] * cols
    for row in body:
        for index, cell in enumerate(row):
            text = _cell_text(cell, cell_limit)
            widths[index] = max(widths[index], len(text))
    lines = []
    for row_index, row in enumerate(body):
        cells = []
        for index in range(cols):
            raw = row[index] if index < len(row) else ""
            text = _cell_text(raw, cell_limit)
            width = widths[index]
            if align and align.get(index) == "r":
                cells.append(text.rjust(width))
            else:
                cells.append(text.ljust(width))
        lines.append("  ".join(cells).rstrip())
        if headers is not None and row_index == 0 and border:
            lines.append("  ".join("-" * w for w in widths))
    return "\n".join(lines)


def _cell_text(value, limit):
    text = str(value)
    if len(text) <= limit:
        return text
    cut = text[: limit - 1]
    head = cut[: cut.rfind(" ")] if " " in cut else cut
    return (head or cut).rstrip() + "…"


def pprint_table(rows, headers=None, align=None, cell_limit=48):
    """Print :func:`format_table` output, terminating the final newline."""
    print(format_table(rows, headers=headers, align=align,
                       cell_limit=cell_limit))


def kv_lines(mapping, key_width=0):
    """Render ``mapping`` as aligned ``key: value`` lines."""
    if not mapping:
        return []
    width = key_width or max(len(str(k)) for k in mapping)
    return [f"{str(k).ljust(width)}: {v}" for k, v in mapping.items()]
