"""Token stream produced by the block lexer and consumed by the parser.

The lexer is deliberately line-oriented: every line of source becomes exactly
one token (or, inside a fenced code block, one ``CODE_LINE`` token), and the
parser assembles runs of tokens into block nodes.  Keeping the token layer so
thin makes the grammar easy to reason about and easy to test.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class TokenKind(Enum):
    """The kinds of line a source document can contain."""

    HEADING = "heading"            # # H1 ... ###### H6
    TEXT = "text"                  # paragraph content
    LIST_ITEM = "list-item"        # '- x', '* x', '1. x' (meta: ordered bool)
    QUOTE = "quote"                # '> quoted text'
    CODE_FENCE_OPEN = "fence-open"  # ```lang
    CODE_LINE = "code-line"        # content inside a fence
    CODE_FENCE_CLOSE = "fence-close"
    INDENTED_CODE = "indent-code"  # 4-space indented line
    ADMONITION = "admonition"      # [note] etc (meta: kind)
    FOOTNOTE_DEF = "footnote-def"  # [^name]: text
    DEFINITION = "definition"      # : definition text
    DIRECTIVE_OPEN = "directive-open"  # {% note %} (meta: tag)
    DIRECTIVE_CLOSE = "directive-close"  # {% endnote %}
    HR = "hr"                      # ---
    INCLUDE = "include"            # {% include "path" %} (text: the path)
    TABLE_ROW = "table-row"        # | a | b |
    BLANK = "blank"                # empty line


@dataclass
class Token:
    """One line of the source document after lexing."""

    kind: TokenKind
    text: str = ""
    level: int = 0
    meta: dict = field(default_factory=dict)

    def __repr__(self):  # pragma: no cover - debugging aid
        meta = ", " + repr(self.meta) if self.meta else ""
        return f"Token({self.kind.value}, {self.text!r}{meta})"
