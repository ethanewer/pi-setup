"""Plain-text extraction from block and inline trees.

Used by the search index and the Atom feed, where markup must be reduced to
searchable prose.
"""

from __future__ import annotations

import re

from quaydoc import inline as _inline
from quaydoc.nodes import (
    Admonition, BlockQuote, CodeBlock, DefinitionList, FootnoteDef, Heading,
    HrBlock, List, ListItem, Paragraph, Table,
)
from quaydoc.util import collapse_ws, shorten

_WS_RE = re.compile(r"\s+")


def plaintext_blocks(blocks):
    """Reduce a block list to plain prose (code bodies included)."""
    parts = []
    for block in blocks:
        if isinstance(block, Paragraph):
            parts.append(_inline.plain_text(block.inlines))
        elif isinstance(block, Heading):
            parts.append(block.title)
        elif isinstance(block, (BlockQuote, Admonition)):
            parts.append(plaintext_blocks(block.children))
        elif isinstance(block, CodeBlock):
            parts.append(block.text)
        elif isinstance(block, Table):
            for row in [block.headers] + block.rows:
                parts.append(" ".join(row))
        elif isinstance(block, List):
            for item in block.items:
                parts.append(plaintext_blocks(item.blocks))
        elif isinstance(block, DefinitionList):
            for term, definitions in block.items.items():
                parts.append(term)
                parts.extend(definitions)
        elif isinstance(block, FootnoteDef):
            parts.append(block.text)
        elif isinstance(block, HrBlock):
            continue
    return " ".join(parts)


def plaintext_inlines(nodes):
    return _inline.plain_text(nodes)


def normalize(text):
    """Whitespace-normalised, collapsed plain text."""
    return _WS_RE.sub(" ", text).strip()


def summary(blocks, limit=240):
    """A shortened plain-text summary of a block list."""
    return shorten(normalize(plaintext_blocks(blocks)), limit)


def word_count(blocks):
    """Approximate word count of a block list's plain text."""
    return len([w for w in plaintext_blocks(blocks).split() if w])
