"""Site navigation (sidebar) construction and rendering.

Navigation comes from two sources merged into one tree: an explicit
``nav`` list in the config, and an automatic listing of every page (in the
config's declared order).  The rendered sidebar is a flat list of rows with
depth classes so the template engine stays recursive-free.
"""

from __future__ import annotations

import os

from quaydoc import theme
from quaydoc.template import Template
from quaydoc.urls import normalize_url


class NavItem:
    """One row of the rendered sidebar."""

    __slots__ = ("title", "url", "depth", "children")

    def __init__(self, title, url, depth=1, children=None):
        self.title = title
        self.url = url
        self.depth = depth
        self.children = children or []

    def rows(self, out=None):
        """Flatten the tree into depth-annotated rows."""
        if out is None:
            out = []
        out.append(self)
        for child in self.children:
            child.rows(out)
        return out


def build_nav(site, groups=None):
    """Build the sidebar rows for a site.

    ``groups`` is an optional list of (label, [page, ...]) pairs; without
    it, all pages form one group.  When the config declares ``nav_groups``
    (a list of ``{label, pages}`` tables), those override the flat order.
    """
    pages = sorted(site.pages, key=lambda p: (p.order, p.slug))
    if groups is None:
        groups = _groups_from_config(site.config)
    if groups:
        rows = []
        seen = set()
        for label, wanted in groups:
            if wanted and all(hasattr(w, "url") for w in wanted):
                group_pages = wanted
            else:
                wanted_set = set(wanted)
                group_pages = [p for p in pages
                               if p.rel_posix in wanted_set or p.url in wanted_set]
            for page in group_pages:
                rows.append(NavItem(label or page.nav_title, page.url, 1))
                seen.add(page.url)
        for page in pages:
            if page.url not in seen:
                rows.append(NavItem(page.nav_title, page.url, 1))
        return rows
    return [NavItem(page.nav_title, page.url, 1) for page in pages]


def _groups_from_config(config):
    """Translate ``config.nav_groups`` into (label, [pages]) groups.

    Group entries are ``{label = "Guides", pages = ["guide/installation.qd"]}``
    style tables; page values match source paths or page URLs.
    """
    raw = getattr(config, "nav_groups", None)
    if not raw:
        return None
    groups = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        label = str(entry.get("label", ""))
        wanted = entry.get("pages", [])
        if isinstance(wanted, str):
            wanted = [wanted]
        groups.append((label, wanted))
    return groups


def _page_rows(page, depth, label):
    rows = [NavItem(label or page.nav_title, page.url, depth)]
    children = []
    for sub in getattr(page, "subpages", []) or []:
        children.extend(_page_rows(sub, depth + 1, None))
    rows[0].children = children
    return rows


def nav_html(site, current_url):
    """Render the sidebar as an HTML string using the theme template."""
    items = build_nav(site)
    current = normalize_url(current_url)
    rows = []
    for item in items:
        for row in item.rows():
            rows.append({
                "title": row.title,
                "url": row.url,
                "depth": row.depth,
                "active": normalize_url(row.url) == current,
            })
    template = Template(theme.TEMPLATES["nav.html"])
    return template.render({
        "nav": rows,
        "current": current,
    })





from dataclasses import dataclass, field


@dataclass
class PageNode:
    """A page plus its computed linear neighbours."""

    page: object
    next_page: object = None
    prev_page: object = None


def linearize(pages):
    """Order pages by (order, slug) and chain next/prev pointers."""
    ordered = sorted(pages, key=lambda p: (p.order, p.slug))
    nodes = [PageNode(page=p) for p in ordered]
    for index, node in enumerate(nodes):
        if index > 0:
            node.prev_page = nodes[index - 1].page
        if index + 1 < len(nodes):
            node.next_page = nodes[index + 1].page
    return nodes


def next_link(node, label="Next"):
    """HTML for the footer next link of ``node`` (or empty)."""
    if node.next_page is None:
        return ""
    return (f'<a class="next-link" href="{node.next_page.url}">'
            f"{label}: {node.next_page.nav_title}</a>")


def prev_link(node, label="Previous"):
    """HTML for the footer previous link of ``node`` (or empty)."""
    if node.prev_page is None:
        return ""
    return (f'<a class="prev-link" href="{node.prev_page.url}">'
            f"{label}: {node.prev_page.nav_title}</a>")


def orphans(pages, referenced):
    """Pages never referenced by any other page's internal links.

    ``referenced`` is the set of page URLs named by at least one other page.
    """
    return [p for p in pages if p.url not in referenced]


def referenced_urls(blocks):
    """Collect every internal link URL named in a block tree."""
    found = set()
    from quaydoc.nodes import (
        Admonition, BlockQuote, ExtLink, List, ListItem, RefLink)

    def walk(node):
        if isinstance(node, RefLink):
            found.add(node.target)
        elif isinstance(node, ExtLink):
            found.add(node.url)

    def walk_blocks(nodes):
        for block in nodes:
            if isinstance(block, (BlockQuote, Admonition)):
                walk_blocks(block.children)
            elif isinstance(block, List):
                for item in block.items:
                    walk_blocks(item.blocks)
            elif isinstance(block, Paragraph):
                for inl in block.inlines:
                    walk(inl)

    walk_blocks(blocks)
    return found
