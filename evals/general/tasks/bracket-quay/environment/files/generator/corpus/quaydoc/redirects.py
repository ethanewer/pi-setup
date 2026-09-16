"""Redirect pages for renamed pages.

A page may declare ``redirect_from: ["/old/path/"]`` (or a single string) in
its front matter.  The build then emits a small HTML page at the old URL
that meta-refreshes to the new one, so stale bookmarks keep working when a
documentation tree is reorganised.
"""

from __future__ import annotations

import posixpath

from quaydoc.util import escape_attr, escape_html, write_text


def collect_redirects(pages):
    """Return ``[(old_url, new_url), ...]`` pairs from page front matter."""
    pairs = []
    for page in pages:
        raw = page.frontmatter.get("redirect_from")
        if raw is None:
            continue
        if isinstance(raw, str):
            raw = [raw]
        for old in raw:
            old = str(old).strip()
            if not old:
                continue
            if not old.startswith("/"):
                old = "/" + old
            pairs.append((old, page.url))
    return pairs


def redirect_html(target_url):
    """A minimal meta-refresh page for ``target_url``."""
    return (
        "<!DOCTYPE html>\n"
        '<html><head><meta charset="utf-8">'
        f'<meta http-equiv="refresh" content="0; url={escape_attr(target_url)}">'
        f"<title>Moved</title></head><body>"
        f'<p>This page moved to <a href="{escape_attr(target_url)}">'
        f"{escape_html(target_url)}</a>.</p></body></html>\n"
    )


def output_for_redirect(old_url, pretty):
    """Output-relative path for a redirect page at ``old_url``."""
    path = old_url.strip("/")
    if not path:
        return "index.html"
    if pretty:
        return posixpath.join(path, "index.html")
    if not path.endswith(".html"):
        return path + ".html"
    return path


def write_redirects(outdir, pairs, pretty):
    """Write one redirect page per pair; returns the number written."""
    written = 0
    for old, new in pairs:
        rel = output_for_redirect(old, pretty)
        write_text(posixpath.join(outdir, rel), redirect_html(new))
        written += 1
    return written
