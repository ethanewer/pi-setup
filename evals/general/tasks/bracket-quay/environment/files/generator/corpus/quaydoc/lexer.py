"""Line-oriented lexer for the quaydoc markup language.

Each source line becomes one :class:`~quaydoc.tokens.Token`; runs of tokens
are assembled into document blocks by :mod:`quaydoc.parser`.  The lexer is
stateful only about fenced code blocks.
"""

from __future__ import annotations

import re

from quaydoc.directives import parse_admonition_line
from quaydoc.errors import ParseError
from quaydoc.tokens import Token, TokenKind

FENCE_MARKER = "```"

_RE_FOOTNOTE_DEF = re.compile(r"^\[\^([A-Za-z0-9_-]+)\]:\s*(.*)$")
_RE_DIRECTIVE = re.compile(r"^\{%\s*([A-Za-z0-9_ -]+)\s*%\}$")
_RE_DEFINITION = re.compile(r"^:\s+.+$")
_FENCE_CLOSE_RE = re.compile(r"`{3,}")
_RE_TABLE_ROW = re.compile(r"^\s*\|.*\|\s*$")

_RE_HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
_RE_LIST = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")
_RE_QUOTE = re.compile(r"^>\s?(.*)$")
_RE_INCLUDE = re.compile(r'^\{%\s*include\s+"([^"]+)"\s*%\}$')
_RE_FENCE = re.compile(r"^(\s*)(`{3,})(.*)$")


def _blank(line):
    return not line.strip()


def lex(text, source="<string>"):
    """Tokenise ``text`` into a list of :class:`Token`.

    Raises :class:`ParseError` for an unclosed code fence (with the line where
    the fence opened).
    """
    tokens = []
    in_fence = False
    fence_lang = None
    fence_indent = 0
    fence_start = None
    fence_run = 3

    for lineno, raw in enumerate(text.split("\n"), 1):
        if in_fence:
            stripped = raw.strip()
            cm = _FENCE_CLOSE_RE.fullmatch(stripped)
            if cm and len(cm.group(0)) >= fence_run:
                tokens.append(Token(TokenKind.CODE_FENCE_CLOSE, "", 0))
                in_fence = False
                fence_lang = None
                fence_run = 3
                continue
            if raw.startswith(" " * fence_indent):
                body = raw[fence_indent:]
            else:
                body = raw
            tokens.append(Token(TokenKind.CODE_LINE, body, 0))
            continue

        if _blank(raw):
            tokens.append(Token(TokenKind.BLANK))
            continue

        fm = _RE_FENCE.match(raw)
        if fm:
            run = fm.group(2)
            lang = fm.group(3).strip()
            tokens.append(Token(TokenKind.CODE_FENCE_OPEN, lang,
                                len(fm.group(1)), {"lang": lang}))
            in_fence = True
            fence_lang = lang
            fence_indent = len(fm.group(1))
            fence_start = lineno
            fence_run = len(run)
            continue

        hm = _RE_HEADING.match(raw)
        if hm:
            tokens.append(Token(TokenKind.HEADING, hm.group(2), len(hm.group(1))))
            continue

        lm = _RE_LIST.match(raw)
        if lm:
            indent = len(lm.group(1))
            ordered = lm.group(2).endswith(".")
            tokens.append(Token(
                TokenKind.LIST_ITEM, lm.group(3), indent // 2,
                {"ordered": ordered, "indent": indent}))
            continue

        qm = _RE_QUOTE.match(raw)
        if qm:
            tokens.append(Token(TokenKind.QUOTE, qm.group(1)))
            continue

        ad = parse_admonition_line(raw)
        if ad is not None:
            kind, rest = ad
            tokens.append(Token(TokenKind.ADMONITION, rest, 0, {"kind": kind}))
            continue

        fdm = _RE_FOOTNOTE_DEF.match(raw)
        if fdm:
            tokens.append(Token(TokenKind.FOOTNOTE_DEF, fdm.group(2), 0,
                                {"name": fdm.group(1)}))
            continue

        if _RE_DEFINITION.match(raw):
            tokens.append(Token(TokenKind.DEFINITION,
                                raw.strip()[2:].strip()))
            continue

        im = _RE_INCLUDE.match(raw)
        if im is not None:
            tokens.append(Token(TokenKind.INCLUDE, im.group(1)))
            continue

        dm = _RE_DIRECTIVE.match(raw)
        if dm:
            tag = dm.group(1).strip().lower()
            if tag.startswith("end"):
                tokens.append(Token(TokenKind.DIRECTIVE_CLOSE,
                                    tag[3:].strip(), 0, {"tag": tag[3:].strip()}))
            else:
                tokens.append(Token(TokenKind.DIRECTIVE_OPEN, tag, 0,
                                    {"tag": tag}))
            continue

        if raw.strip() == "---":
            tokens.append(Token(TokenKind.HR))
            continue

        if _RE_TABLE_ROW.match(raw):
            tokens.append(Token(TokenKind.TABLE_ROW, raw))
            continue

        if raw.startswith("    ") and raw.strip():
            tokens.append(Token(TokenKind.INDENTED_CODE, raw[4:]))
            continue

        tokens.append(Token(TokenKind.TEXT, raw))

    if in_fence:
        raise ParseError(source, fence_start, "unclosed code fence")

    return tokens
