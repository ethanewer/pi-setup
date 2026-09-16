"""Atom feed generation (``feed.xml``).

One entry per page, ordered by date (undated pages sort last).  Entry ids
are derived from the canonical page URL so feeds survive host moves; the
updated timestamp comes from the page's ``date`` front matter when present
and the build time otherwise.
"""

from __future__ import annotations

import os

from quaydoc.util import escape_html, now_iso


def _entry_id(base_url, url):
    return (base_url.rstrip("/") + url).strip(" ") or url


def build_feed(pages, config):
    """Return an Atom feed document for ``pages``."""
    base = (config.base_url or "").rstrip("/")
    site_url = base + "/" if base else "/"
    entries = []
    for page in sorted(pages, key=lambda p: str(p.date or "")):
        modified = page.date.isoformat() if page.date else now_iso()
        entries.append(
            f"  <entry>\n"
            f"    <title>{escape_html(page.title)}</title>\n"
            f"    <link href=\"{escape_html(base + page.url)}\" "
            f"rel=\"alternate\"/>\n"
            f"    <id>{escape_html(_entry_id(base, page.url))}</id>\n"
            f"    <updated>{modified}</updated>\n"
            f"    <summary>{escape_html(page.description or page.title)}"
            f"</summary>\n"
            f"    <content type=\"html\">{escape_html(page.title)}"
            f"</content>\n"
            f"  </entry>")
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<feed xmlns="http://www.w3.org/2005/Atom">',
        f"  <title>{escape_html(config.title)}</title>",
        f"  <id>{escape_html(site_url)}</id>",
        f"  <updated>{now_iso()}</updated>",
        f"  <link href=\"{escape_html(site_url)}\" rel=\"alternate\"/>",
    ]
    parts.extend(entries)
    parts.append("</feed>")
    return "\n".join(parts) + "\n"


def rss2_feed(pages, config):
    """Return an RSS 2.0 feed for ``pages`` (Atom stays the default).

    ``pubDate`` uses RFC 822 dates from the page's ``date`` front matter,
    falling back to the build time; ``guid`` is the canonical page URL.
    """
    import email.utils
    from datetime import datetime, timezone

    base = (config.base_url or "").rstrip("/")
    site_url = base + "/" if base else "/"
    items = []
    for page in sorted(pages, key=lambda p: str(p.date or "")):
        stamp = page.date if page.date else datetime.now(timezone.utc)
        pub_date = stamp.astimezone(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")
        url = base + page.url
        items.append(
            f"    <item>\n"
            f"      <title>{escape_html(page.title)}</title>\n"
            f"      <link>{escape_html(url)}</link>\n"
            f"      <guid isPermaLink=\"true\">{escape_html(url)}</guid>\n"
            f"      <pubDate>{pub_date}</pubDate>\n"
            f"      <description>{escape_html(page.description or page.title)}"
            f"</description>\n"
            f"    </item>")
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<rss version=\"2.0\">",
        "  <channel>",
        f"    <title>{escape_html(config.title)}</title>",
        f"    <link>{escape_html(site_url)}</link>",
        f"    <description>{escape_html(config.description or config.title)}"
        f"</description>",
    ]
    parts.extend(items)
    parts.append("  </channel>")
    parts.append("</rss>")
    return "\n".join(parts) + "\n"
