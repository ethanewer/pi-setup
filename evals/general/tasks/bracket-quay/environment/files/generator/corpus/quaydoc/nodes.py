"""Document node types.

The parser produces a tree of :class:`Block` nodes; inline content inside a
block is a list of :class:`Inline` nodes.  Renderers walk these trees; the
nodes themselves carry no formatting.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional


# ---------------------------------------------------------------------------
# Inline nodes
# ---------------------------------------------------------------------------

class Inline:
    """Base class for inline content."""


@dataclass
class Text(Inline):
    """Literal text."""

    text: str


@dataclass
class Bold(Inline):
    """``**bold**`` — children are inline nodes."""

    children: List[Inline] = field(default_factory=list)


@dataclass
class CodeSpan(Inline):
    """``` ``code`` ``` — verbatim, never parsed as markup."""

    code: str


@dataclass
class FootnoteRef(Inline):
    """``[^name]`` inline footnote reference."""

    name: str


@dataclass
class RefLink(Inline):
    """``[[target|label]]`` internal link.

    ``target`` is a page title, a heading title, or a relative page path;
    ``label`` defaults to the target.
    """

    target: str
    label: str


@dataclass
class ExtLink(Inline):
    """``[label](url)`` external or relative link."""

    label: str
    url: str


@dataclass
class Image(Inline):
    """``![alt](src)`` (or ``![alt](src "title")``) image reference."""

    alt: str
    src: str
    title: Optional[str] = None


# ---------------------------------------------------------------------------
# Block nodes
# ---------------------------------------------------------------------------

class Block:
    """Base class for block-level content."""


@dataclass
class Heading(Block):
    """A ``#``-prefixed heading.

    ``anchor`` is assigned at render time; a trailing ``{#custom-id}`` /
    ``{.class}`` suffix on the source line overrides both the anchor and the
    rendered class list.  ``clean_title`` is the title without the suffix.
    """

    level: int
    title: str
    anchor: Optional[str] = None
    clean_title: Optional[str] = None
    custom_id: Optional[str] = None
    classes: List[str] = field(default_factory=list)


@dataclass
class Paragraph(Block):
    """A run of text lines rendered as one ``<p>``."""

    inlines: List[Inline] = field(default_factory=list)


@dataclass
class ListItem(Block):
    """One item of a list; ``children`` are the blocks inside the item."""

    ordered: bool
    blocks: List[Block] = field(default_factory=list)


@dataclass
class List(Block):
    """A run of list items.  Mixed ordered/unordered runs are allowed; the
    renderer splits them back into separate ``<ul>`` / ``<ol>`` groups."""

    items: List[ListItem] = field(default_factory=list)


@dataclass
class BlockQuote(Block):
    """A ``>`` block quote; ``children`` are parsed blocks."""

    children: List[Block] = field(default_factory=list)


@dataclass
class CodeBlock(Block):
    """A fenced or indented code block."""

    lang: Optional[str]
    text: str


@dataclass
class Admonition(Block):
    """A ``[kind]`` callout; ``children`` are its body blocks."""

    kind: str
    children: List[Block] = field(default_factory=list)


@dataclass
class HrBlock(Block):
    """A thematic break."""


@dataclass
class FootnoteDef(Block):
    """A ``[^name]: text`` footnote definition line."""

    name: str
    text: str


@dataclass
class DefinitionList(Block):
    """A ``term`` / ``: definition`` list."""

    items: dict = field(default_factory=dict)


@dataclass
class Table(Block):
    """A pipe table.

    ``headers`` are the column titles (inline-parsed at render time);
    ``rows`` is a list of cell strings.  Cells are raw text and are parsed
    as inline markup when rendered, so links inside table cells work.
    """

    headers: List[str] = field(default_factory=list)
    rows: List[List[str]] = field(default_factory=list)

    @property
    def column_count(self):
        return len(self.headers) or (len(self.rows[0]) if self.rows else 0)
