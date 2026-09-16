"""Snippet mode: embeddable page fragments.

With ``[build] snippet = true`` every page is additionally rendered as a
bare fragment — content only, no shell, no navigation — under
``_snippets/<url path>.html``.  Documentation portals that embed quaydoc
pages inside a larger application use these instead of the full page.
"""

from __future__ import annotations

import os

from quaydoc import blocks
from quaydoc.util import write_text


def render_snippet(page, site):
    """Render just a page's content blocks (footnotes included)."""
    ctx = blocks.RenderContext(page, site, site.resolver)
    body = blocks.render_blocks(page.blocks, ctx)
    body += blocks.render_footnotes(page.blocks, ctx)
    return body


def write_snippets(site, outdir):
    """Write one ``_snippets/...`` fragment per page; returns the count."""
    count = 0
    for page in site.pages:
        rel = page.out_rel
        if rel == "index.html":
            dest = "_snippets/index.html"
        elif rel.endswith("/index.html"):
            dest = "_snippets/" + rel[: -len("index.html")] + ".html"
        else:
            dest = "_snippets/" + rel
        write_text(os.path.join(outdir, dest), render_snippet(page, site))
        count += 1
    return count
