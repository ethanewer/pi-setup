"""Inline markup parser.

Recognised constructs (all but ``**`` and backticks are left alone when
unclosed, so stray markup degrades to literal text):

================  ================================
``**bold**``      bold run (nesting ignored inside)
`` `code` ``       code span (verbatim)
``[[target]]``    internal link, label == target
``[[target|label]]``  internal link with label
``[label](url)``  external / relative link
``![alt](src)``   image
``\\x``            literal x
================  ================================
"""

from __future__ import annotations

from typing import List

import re

from quaydoc.nodes import (Bold, CodeSpan, ExtLink, FootnoteRef,
                          Image, Inline, RefLink, Text)

_BOLD = "**"
_CODE = "`"


def parse_inline(text: str) -> List[Inline]:
    """Parse a string of inline markup into inline nodes."""
    return _parse(text, 0, len(text), allow_links=True)


def _find(text, needle, start, end):
    """Index of the next unescaped occurrence of ``needle`` in
    ``text[start:end]``, or ``-1``."""
    i = text.find(needle, start, end)
    while i != -1 and i > start and text[i - 1] == "\\":
        i = text.find(needle, i + 1, end)
    return i


def _parse(text, start, end, allow_links):
    nodes: List[Inline] = []
    i = start
    buf = []

    def flush():
        if buf:
            nodes.append(Text("".join(buf)))
            del buf[:]

    while i < end:
        ch = text[i]

        if ch == "\\" and i + 1 < end:
            buf.append(text[i + 1])
            i += 2
            continue

        if text.startswith(_BOLD, i):
            close = _find(text, _BOLD, i + 2, end)
            if close > i + 2:
                flush()
                inner = _parse(text, i + 2, close, allow_links=True)
                nodes.append(Bold(inner))
                i = close + 2
                continue
            buf.append(_BOLD)
            i += 2
            continue

        if ch == _CODE:
            close = _find(text, _CODE, i + 1, end)
            if close > i:
                flush()
                nodes.append(CodeSpan(text[i + 1:close]))
                i = close + 1
                continue
            buf.append(_CODE)
            i += 1
            continue

        if allow_links and text.startswith("[^", i):
            close = _find(text, "]", i + 2, end)
            if close > i + 2:
                flush()
                nodes.append(FootnoteRef(text[i + 2:close]))
                i = close + 1
                continue
            buf.append("[^")
            i += 2
            continue

        if allow_links and text.startswith("![", i):
            alt_end = _find(text, "]", i + 2, end)
            src_end = _find(text, ")", alt_end + 1, end) if alt_end != -1 else -1
            if alt_end != -1 and src_end != -1 and \
                    text[alt_end + 1:alt_end + 2] == "(":
                flush()
                raw_src = text[alt_end + 2:src_end]
                src = raw_src
                title = None
                if " " in raw_src and raw_src.endswith(('"', "'")):
                    maybe_src, _, quoted = raw_src.rpartition(" ")
                    if quoted[:1] in ('"', "'") and quoted[-1:] == quoted[:1]:
                        src, title = maybe_src, quoted[1:-1]
                nodes.append(Image(text[i + 2:alt_end], src, title))
                i = src_end + 1
                continue
            buf.append("![")
            i += 2
            continue

        if allow_links and text.startswith("[[", i):
            close = _find(text, "]]", i + 2, end)
            if close > i + 2:
                flush()
                inner = text[i + 2:close]
                if "|" in inner:
                    target, label = inner.split("|", 1)
                else:
                    target = label = inner
                nodes.append(RefLink(target.strip(), label.strip()))
                i = close + 2
                continue
            buf.append("[[")
            i += 2
            continue

        if allow_links and ch == "[":
            close = _find(text, "]", i + 1, end)
            if close > i:
                if text[close + 1:close + 2] == "(":
                    url_end = _find(text, ")", close + 2, end)
                    if url_end > close + 2:
                        flush()
                        nodes.append(ExtLink(text[i + 1:close],
                                             text[close + 2:url_end]))
                        i = url_end + 1
                        continue
            buf.append(ch)
            i += 1
            continue

        buf.append(ch)
        i += 1

    flush()
    return nodes


def plain_text(nodes: List[Inline]) -> str:
    """Reconstruct plain text from inline nodes (used by search/feeds)."""
    parts = []
    for node in nodes:
        if isinstance(node, Text):
            parts.append(node.text)
        elif isinstance(node, Bold):
            parts.append(plain_text(node.children))
        elif isinstance(node, CodeSpan):
            parts.append(node.code)
        elif isinstance(node, RefLink):
            parts.append(node.label)
        elif isinstance(node, FootnoteRef):
            continue
        elif isinstance(node, ExtLink):
            parts.append(node.label)
        elif isinstance(node, Image):
            parts.append(node.alt)
    return "".join(parts)



EMOJI = {
    "smile": "🙂", "grin": "😀", "wink": "😉", "cry": "😢",
    "thumbsup": "👍", "thumbsdown": "👎", "clap": "👏", "wave": "👋",
    "rocket": "🚀", "sparkles": "✨", "check": "✅", "cross": "❌",
    "warning": "⚠️", "stop": "🛑", "fire": "🔥", "star": "⭐",
    "heart": "❤️", "book": "📖", "bulb": "💡", "gear": "⚙️",
    "wrench": "🔧", "bug": "🐛", "info": "ℹ️", "question": "❓",
    "point_up": "☝️", "point_right": "👉", "arrow_right": "➡️",
    "arrow_left": "⬅️", "arrow_up": "⬆️", "arrow_down": "⬇️",
    "package": "📦", "wrench": "🔧", "hammer": "🔨", "folder": "📁",
    "file": "📄", "lock": "🔒", "unlock": "🔓", "key": "🗝️",
    "hourglass": "⏳", "calendar": "📅", "clock": "🕐", "bell": "🔔",
    "memo": "📝", "pencil": "✏️", "scissors": "✂️", "printer": "🖨️",
    "link": "🔗", "chain": "⛓️", "tag": "🏷️", "label": "🔖",
    "sun": "☀️", "cloud": "☁️", "rain": "🌧️", "bolt": "⚡",
    "snow": "❄️", "wind": "🍃", "fire_extinguisher": "🧯",
    "shield": "🛡️", "helmet": "⛑️", "first_aid": "⛑️",
    "chart": "📊", "graph": "📈", "pie": "🥧", "magnify": "🔍",
    "globe": "🌐", "satellite": "🛰️", "phone": "📞", "mail": "✉️",
    "inbox": "📥", "outbox": "📤", "clipboard": "📋",
}

_SHORTCODE_RE = re.compile(r":([A-Za-z0-9_]+):")


def expand(text):
    """Replace ``:name:`` shortcodes in plain text with emoji."""
    return _SHORTCODE_RE.sub(
        lambda m: EMOJI.get(m.group(1), m.group(0)), text)


def known(name):
    return name in EMOJI


expand_emoji = expand


def names():
    """Sorted list of known shortcode names (for completion tooling)."""
    return sorted(EMOJI)
