"""Block and inline renderers: node trees to HTML fragments.

Rendering is context-driven: the :class:`RenderContext` carries the page
being rendered, the site-wide resolver, and the page's anchor map, so a
heading's ``id`` and a ``[[...]]`` reference's ``href`` both come from the
same render pass.
"""

from __future__ import annotations

from dataclasses import dataclass

from quaydoc import directives, highlight, inline as _inline
from quaydoc.links import LinkResolver
from quaydoc.nodes import (
    Admonition, Block, BlockQuote, Bold, CodeBlock, CodeSpan,
    DefinitionList, ExtLink, FootnoteDef, FootnoteRef, Heading, HrBlock,
    Image, List, ListItem, Paragraph, RefLink, Table, Text,
)
from quaydoc.util import escape_attr, escape_html
import re as _re

_DIAGRAM_LANGS = ("mermaid", "graph", "sequence")


@dataclass
class RenderContext:
    """Everything a render pass needs to produce a page fragment."""

    page: object
    site: object
    resolver: LinkResolver

    @property
    def anchor_map(self):
        return self.page.anchor_map


def render_blocks(blocks, ctx):
    """Render a list of blocks to an HTML fragment."""
    return "".join(_render_one(block, ctx) for block in blocks)


def render_inlines(nodes, ctx):
    """Render a list of inline nodes to an HTML fragment."""
    return "".join(_render_inline(node, ctx) for node in nodes)


def _render_one(node, ctx):
    if isinstance(node, Heading):
        anchor = node.custom_id or ctx.anchor_map.lookup(node.title)
        if anchor is None:
            anchor = ctx.anchor_map.take(node.title)
        title_html = render_inlines(_inline.parse_inline(node.title), ctx)
        number = ctx.page.section_numbers.get(node.title) if hasattr(
            ctx.page, "section_numbers") else None
        if number:
            title_html = f'<span class="section-number">{number}</span> ' \
                + title_html
        attrs = f' id="{escape_attr(anchor)}"'
        if node.classes:
            attrs += f' class="{escape_attr(" ".join(node.classes))}"'
        return f"<h{node.level}{attrs}>{title_html}</h{node.level}>"
    if isinstance(node, Paragraph):
        return f"<p>{render_inlines(node.inlines, ctx)}</p>"
    if isinstance(node, List):
        return _render_list(node, ctx)
    if isinstance(node, BlockQuote):
        inner = render_blocks(node.children, ctx)
        return f"<blockquote>{inner}</blockquote>"
    if isinstance(node, CodeBlock):
        return _render_code(node, ctx)
    if isinstance(node, Admonition):
        return _render_admonition(node, ctx)
    if isinstance(node, HrBlock):
        return "<hr>"
    if isinstance(node, Table):
        return _render_table(node, ctx)
    if isinstance(node, DefinitionList):
        return _render_definition_list(node, ctx)
    if isinstance(node, FootnoteDef):
        return ""  # rendered once, in the footnotes section
    return ""


def _render_table(node, ctx):
    out = ['<table class="doc-table">']
    if node.headers:
        out.append("<thead><tr>")
        for cell in node.headers:
            out.append(f"<th>{render_inlines(_inline.parse_inline(cell), ctx)}</th>")
        out.append("</tr></thead>")
    if node.rows:
        out.append("<tbody>")
        for row in node.rows:
            out.append("<tr>")
            for cell in row:
                out.append(f"<td>{render_inlines(_inline.parse_inline(cell), ctx)}</td>")
            out.append("</tr>")
        out.append("</tbody>")
    out.append("</table>")
    return "".join(out)


def _render_taskbox(item_blocks, body, ctx):
    """Turn a leading ``[ ]`` / ``[x]`` marker into a checkbox."""
    if not item_blocks or not isinstance(item_blocks[0], Paragraph):
        return body
    first = item_blocks[0].inlines
    if not first or not isinstance(first[0], Text):
        return body
    text = first[0].text
    if not (text.startswith("[ ] ") or text.startswith("[x] ")):
        return body
    checked = text.startswith("[x] ")
    rest = text[4:]
    first[0] = Text(rest)
    box = (f'<input type="checkbox" class="task-check" disabled'
           f'{" checked" if checked else ""}> ')
    return _re.sub(r"^<p>", "<p>" + box, body)


def _render_definition_list(node, ctx):
    out = ['<dl class="definition-list">']
    for term, definitions in node.items.items():
        out.append(f"<dt>{escape_html(term)}</dt>")
        for definition in definitions:
            cells = render_inlines(_inline.parse_inline(definition), ctx)
            out.append(f"<dd>{cells}</dd>")
    out.append("</dl>")
    return "".join(out)


def render_footnotes(blocks, ctx):
    """Render the collected footnote section for a page (or empty)."""
    counter = {}
    ordered = []
    for block in blocks:
        if isinstance(block, FootnoteDef):
            if block.name in counter:
                continue
            counter[block.name] = len(ordered) + 1
            ordered.append(block)
    ctx.page.footnote_numbers = counter
    if not ordered:
        return ""
    items = []
    for block in ordered:
        cells = render_inlines(_inline.parse_inline(block.text), ctx)
        items.append(f'<li id="fn-{escape_attr(block.name)}">{cells} '
                     f'<a href="#fnref-{escape_attr(block.name)}">↩</a></li>')
    return ('<section class="footnotes"><h2>Footnotes</h2><ol>'
            + "".join(items) + "</ol></section>")


def _render_list(node, ctx):
    out = []
    group = None
    for item in node.items:
        if item.ordered != group:
            group = item.ordered
            if len(out) > 1:
                out.insert(len(out) - 1, _close(group))
            tag = "ol" if item.ordered else "ul"
            out.append(f"<{tag}>")
        body = render_blocks(item.blocks, ctx)
        if not item.ordered:
            body = _render_taskbox(item.blocks, body, ctx)
        out.append("<li>")
        out.append(body)
        out.append("</li>")
    if out:
        last_tag = "ol" if group else "ul"
        out.append(f"</{last_tag}>")
    return "".join(out)


def _close(group):
    return "</ol>" if group else "</ul>"


def _render_code(node, ctx):
    lang = node.lang or ""
    if lang in _DIAGRAM_LANGS:
        return (f'<div class="diagram diagram-{escape_attr(lang)}">'
                f'<pre class="diagram-source">{escape_html(node.text)}</pre>'
                f"</div>")
    if lang:
        body = highlight.highlight(node.text, lang)
    else:
        body = escape_html(node.text)
    lang_cls = f' class="language-{escape_attr(lang)}"' if lang else ""
    return f'<pre class="highlight"><code{lang_cls}>{body}</code></pre>'


def _render_admonition(node, ctx):
    label = directives.admonition_label(node.kind)
    body = render_blocks(node.children, ctx)
    cls = directives.admonition_css_class(node.kind)
    return (f'<div class="{escape_attr(cls)}"><p class="admonition-title">'
            f"{escape_html(label)}</p>{body}</div>")


def _render_inline(node, ctx):
    if isinstance(node, Text):
        return escape_html(_inline.expand_emoji(node.text))
    if isinstance(node, FootnoteRef):
        number = ctx.page.footnote_numbers.get(node.name, 1)
        return (f'<sup class="footnote-ref" id="fnref-{escape_attr(node.name)}">'
                f'<a href="#fn-{escape_attr(node.name)}">{number}</a></sup>')
    if isinstance(node, Bold):
        return f"<strong>{render_inlines(node.children, ctx)}</strong>"
    if isinstance(node, CodeSpan):
        return f"<code>{escape_html(node.code)}</code>"
    if isinstance(node, RefLink):
        result = ctx.resolver.resolve(node.target, ctx.page)
        cls = ' class="missing"' if not result.ok else ""
        return (f'<a href="{escape_attr(result.url)}"{cls}>'
                f"{escape_html(node.label)}</a>")
    if isinstance(node, ExtLink):
        href = node.url
        cls = ""
        if not _is_external(href):
            result = ctx.resolver.resolve_path(href, ctx.page)
            href, cls = result.url, ("" if result.ok else ' class="missing"')
        return (f'<a href="{escape_attr(href)}"{cls}>'
                f"{escape_html(node.label)}</a>")
    if isinstance(node, Image):
        result = ctx.resolver.resolve_path(node.src, ctx.page)
        cls = ' class="missing"' if not result.ok else ""
        title = f' title="{escape_attr(node.title)}"' if node.title else ""
        return (f'<img src="{escape_attr(result.url)}" '
                f'alt="{escape_attr(node.alt)}"{title}{cls}>')
    return ""


def _is_external(url):
    return url.startswith(("http://", "https://", "mailto:", "ftp://", "//",
                           "#", "data:"))
