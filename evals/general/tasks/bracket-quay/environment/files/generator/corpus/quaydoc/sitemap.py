"""Sitemap generation (``sitemap.xml``).

Every built page is listed with its last-modified date where the page's
front matter provides one.  The checker cross-validates the sitemap against
the pages actually written.
"""

from __future__ import annotations

from quaydoc.util import escape_html, now_iso


def build_sitemap(pages, base_url=""):
    """Return ``sitemap.xml`` for ``pages`` under ``base_url``."""
    base = (base_url or "").rstrip("/")
    parts = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for page in pages:
        loc = escape_html(base + page.url)
        parts.append("  <url>")
        parts.append(f"    <loc>{loc}</loc>")
        if page.date:
            parts.append(f"    <lastmod>{page.date.isoformat()}</lastmod>")
        parts.append("  </url>")
    parts.append("</urlset>")
    return "\n".join(parts) + "\n"
