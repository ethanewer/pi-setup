"""Block parser: tokens to document tree.

Assembly rules are kept simple and deterministic:

* consecutive ``TEXT`` tokens are one paragraph,
* consecutive ``LIST_ITEM`` tokens (possibly nested by indent) are one list,
* consecutive ``QUOTE`` tokens are a block quote whose body is parsed
  recursively,
* a fence run is a code block,
* an admonition takes the rest of its line plus the following text lines,
* an ``{% include %}`` is expanded inline (depth- and root-bounded),
* blank lines terminate open runs.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, List, Optional

from quaydoc import inline as _inline
from quaydoc import lexer
from quaydoc import meta as _meta
from quaydoc.errors import ParseError, SourceError
import re as _re

KNOWN_DIRECTIVES = ("note", "tip", "warn", "danger", "info", "code",
                    "details", "quote")
from quaydoc.nodes import (
    Admonition, Block, BlockQuote, CodeBlock, DefinitionList, FootnoteDef,
    Heading, HrBlock, List, ListItem, Paragraph, Table,
)
from quaydoc.tokens import Token, TokenKind

MAX_INCLUDE_DEPTH = 8

Includer = Callable[[str, str], str]  # (include_path, source_path) -> text


@dataclass
class Document:
    """A parsed source document."""

    frontmatter: dict = field(default_factory=dict)
    blocks: List[Block] = field(default_factory=list)
    headings: List[tuple] = field(default_factory=list)  # (level, title)
    source: str = "<string>"
    warnings: List[str] = field(default_factory=list)


def parse_document(text, source="<string>", includer=None):
    """Parse full document text into a :class:`Document`."""
    frontmatter, body = _meta.parse_frontmatter(text)
    tokens = lexer.lex(body, source)
    blocks, headings = parse_blocks_with_headings(
        tokens, source, includer=includer, seen=set(), depth=0)
    warnings = _meta.validate_frontmatter(frontmatter, source)
    return Document(frontmatter, blocks, headings, source, warnings)


def parse_inline_text(text):
    """Parse a string of inline markup (e.g. an item label)."""
    return _inline.parse_inline(text)


def parse_blocks_with_headings(tokens, source, includer=None, seen=None,
                               depth=0):
    """Parse a token stream; also return the flat heading list."""
    blocks, _ = _parse_blocks(tokens, source, includer, seen, depth)
    headings = _collect_headings(blocks, out=None)
    return blocks, headings


def _parse_blocks(tokens, source, includer, seen, depth):
    blocks: List[Block] = []
    headings = []
    i = 0
    n = len(tokens)
    while i < n:
        tok = tokens[i]

        if tok.kind is TokenKind.BLANK:
            i += 1
            continue

        if tok.kind is TokenKind.HEADING:
            child = [tok]
            i += 1
            while i < n and tokens[i].kind is TokenKind.TEXT:
                child.append(tokens[i])
                i += 1
            text = " ".join(t.text for t in child)
            clean, custom_id, classes = _parse_heading_suffix(text)
            blocks.append(Heading(tok.level, clean, None, clean,
                                  custom_id, classes))
            headings.append((tok.level, clean))
            continue

        if tok.kind is TokenKind.TEXT:
            run = [tok]
            i += 1
            while i < n and tokens[i].kind is TokenKind.TEXT and \
                    not (i + 1 < n and
                         tokens[i + 1].kind is TokenKind.DEFINITION):
                run.append(tokens[i])
                i += 1
            text = " ".join(t.text for t in run)
            blocks.append(Paragraph(_inline.parse_inline(text)))
            continue

        if tok.kind is TokenKind.FOOTNOTE_DEF:
            blocks.append(FootnoteDef(tok.meta["name"], tok.text))
            i += 1
            continue

        if tok.kind is TokenKind.DEFINITION:
            # the single text line immediately before forms the term(s)
            term = ""
            if blocks and isinstance(blocks[-1], Paragraph) and \
                    len(blocks[-1].inlines) == 1 and \
                    isinstance(blocks[-1].inlines[0], _inline.Text):
                term = blocks[-1].inlines[0].text
                blocks.pop()
            node, i = _parse_definition_list(tokens, i, term, source,
                                             includer, seen, depth)
            blocks.append(node)
            continue

        if tok.kind is TokenKind.LIST_ITEM:
            node, i = _parse_list(tokens, i, source, includer, seen, depth)
            blocks.append(node)
            continue

        if tok.kind is TokenKind.QUOTE:
            run = [tok]
            i += 1
            while i < n and tokens[i].kind is TokenKind.QUOTE:
                run.append(tokens[i])
                i += 1
            sub = [Token(TokenKind.TEXT, t.text) for t in run]
            children, _ = _parse_blocks(sub, source, includer, seen, depth)
            blocks.append(BlockQuote(children))
            continue

        if tok.kind is TokenKind.CODE_FENCE_OPEN:
            lines = []
            start = tok.text
            i += 1
            while i < n and tokens[i].kind is not TokenKind.CODE_FENCE_CLOSE:
                lines.append(tokens[i].text)
                i += 1
            if i >= n:
                raise ParseError(source, None, "unclosed code fence")
            i += 1  # consume close token
            blocks.append(CodeBlock(tok.meta.get("lang") or None,
                                    "\n".join(lines)))
            continue

        if tok.kind is TokenKind.INDENTED_CODE:
            run = [tok]
            i += 1
            while i < n and tokens[i].kind is TokenKind.INDENTED_CODE:
                run.append(tokens[i])
                i += 1
            blocks.append(CodeBlock(None, "\n".join(t.text for t in run)))
            continue

        if tok.kind is TokenKind.ADMONITION:
            body_tokens = [Token(TokenKind.TEXT, t)
                           for t in (tok.text,) if t.strip()]
            i += 1
            while i < n and tokens[i].kind is TokenKind.TEXT:
                body_tokens.append(tokens[i])
                i += 1
            children, _ = _parse_blocks(body_tokens, source, includer, seen,
                                        depth)
            blocks.append(Admonition(tok.meta["kind"], children))
            continue

        if tok.kind is TokenKind.TABLE_ROW:
            run = [tok]
            i += 1
            while i < n and tokens[i].kind is TokenKind.TABLE_ROW:
                run.append(tokens[i])
                i += 1
            blocks.append(_assemble_table(run))
            continue

        if tok.kind is TokenKind.DIRECTIVE_OPEN:
            tag = tok.meta["tag"]
            if tag not in KNOWN_DIRECTIVES:
                raise ParseError(source, None,
                                 f"unknown directive {tag!r} "
                                 f"(known: {', '.join(KNOWN_DIRECTIVES)})")
            body_tokens = []
            i += 1
            while i < n and tokens[i].kind is not TokenKind.DIRECTIVE_CLOSE:
                body_tokens.append(tokens[i])
                i += 1
            if i >= n:
                raise ParseError(source, None,
                                 f"directive {tag!r} is never closed")
            i += 1  # consume close
            children, _ = _parse_blocks(body_tokens, source, includer, seen,
                                        depth)
            if tag == "quote":
                blocks.append(BlockQuote(children))
            elif tag == "code":
                text = "\n".join(
                    _block_text(c) for c in children)
                blocks.append(CodeBlock(None, text))
            else:
                blocks.append(Admonition(tag, children))
            continue

        if tok.kind is TokenKind.INCLUDE:
            if depth >= MAX_INCLUDE_DEPTH:
                raise SourceError(
                    f"{source}: include nesting exceeds "
                    f"{MAX_INCLUDE_DEPTH} levels ({tok.text!r})")
            if includer is None:
                raise SourceError(f"{source}: include {tok.text!r} but no "
                                  "includer is configured")
            text = includer(tok.text, source)
            sub_tokens = lexer.lex(text, f"{source} -> include {tok.text}")
            child_blocks, _ = _parse_blocks(
                sub_tokens, f"{source} (include {tok.text})", includer,
                seen, depth + 1)
            blocks.extend(child_blocks)
            i += 1
            continue

        if tok.kind is TokenKind.HR:
            blocks.append(HrBlock())
            i += 1
            continue

        i += 1  # unknown token kinds are skipped defensively

    return blocks, headings


def _parse_list(tokens, i, source, includer, seen, depth):
    """Parse a run of list items starting at ``i`` (an item token)."""
    n = len(tokens)
    items = []
    while i < n and tokens[i].kind is TokenKind.LIST_ITEM:
        tok = tokens[i]
        level = tok.level
        content = tok.text
        j = i + 1
        sub_tokens = []
        while j < n and tokens[j].kind is TokenKind.LIST_ITEM and \
                tokens[j].level > level:
            # strip the item's own indent so the recursion sees relative ones
            sub = tokens[j]
            sub_tokens.append(Token(sub.kind, sub.text, sub.level - level - 1,
                                    dict(sub.meta)))
            j += 1
        children = []
        if content.strip():
            children.append(Paragraph(_inline.parse_inline(content)))
        if sub_tokens:
            sub_items, _ = _parse_blocks(sub_tokens, source, includer, seen,
                                         depth)
            for sub_block in sub_items:
                children.append(sub_block)
        items.append(ListItem(bool(tok.meta.get("ordered")), children))
        i = j
    return List(items), i


def _collect_headings(blocks, out=None):
    """Collect every (level, title) heading pair, flattening containers."""
    if out is None:
        out = []
    for block in blocks:
        if isinstance(block, Heading):
            out.append((block.level, block.title))
        elif isinstance(block, (List, ListItem)):
            for item in getattr(block, "items", ()):
                _collect_headings(item.blocks, out)
        elif isinstance(block, (BlockQuote, Admonition)):
            _collect_headings(block.children, out)
    return out


def _split_cells(line):
    """Split a pipe-table line into cells (trimmed, outer pipes dropped)."""
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [cell.strip() for cell in line.split("|")]


def _is_delimiter(cells):
    """True when every cell looks like a ``---`` / ``-:-`` separator row."""
    if not cells:
        return False
    return all(_re.fullmatch(r":?-{2,}:?", cell or "") for cell in cells)


def _assemble_table(tokens):
    """Turn a run of TABLE_ROW tokens into a Table node."""
    rows = [_split_cells(tok.text) for tok in tokens]
    width = max((len(row) for row in rows), default=0)
    rows = [row + [""] * (width - len(row)) for row in rows]

    headers = []
    body = rows
    if len(rows) >= 2 and _is_delimiter(rows[1]):
        headers = list(rows[0])
        body = rows[2:]
    elif len(rows) >= 1 and _is_delimiter(rows[0]):
        body = rows[1:]
    return Table(headers=headers, rows=body)


def _parse_definition_list(tokens, i, term, source, includer, seen, depth):
    """Parse a run of DEFINITION tokens into a DefinitionList node."""
    items = {}
    while i < len(tokens) and tokens[i].kind is TokenKind.DEFINITION:
        items.setdefault(term, []).append(tokens[i].text)
        i += 1
    return DefinitionList(items), i


def _block_text(block):
    """Crude plain text of a block for ``{% code %}`` bodies."""
    from quaydoc import inline as _i
    from quaydoc.nodes import Paragraph
    if isinstance(block, Paragraph):
        return _i.plain_text(block.inlines)
    return ""

_HEADING_SUFFIX = _re.compile(
    r"\s*\{((?:#[A-Za-z0-9_-]+|\.[A-Za-z0-9_-]+)"
    r"(?:\s+(?:#[A-Za-z0-9_-]+|\.[A-Za-z0-9_-]+))*)\}\s*$")


def _parse_heading_suffix(title):
    """Split a trailing ``{#id}`` / ``{.a .b}`` suffix off a title.

    Returns ``(clean_title, custom_id, classes)``.
    """
    m = _HEADING_SUFFIX.search(title)
    if not m:
        return title, None, []
    suffix = m.group(1)
    clean = title[:m.start()].strip()
    custom_id = None
    classes = []
    for token in _re.findall(r"#[A-Za-z0-9_-]+|\.[A-Za-z0-9_-]+", suffix):
        if token.startswith("#"):
            custom_id = token[1:]
        else:
            classes.append(token[1:])
    return clean, custom_id, classes
