"""Link resolution: ``[[...]]`` references and ``[..](url)`` links.

Fragment targets for headings are computed here with :func:`target_for`,
which must agree exactly with the ``id`` attributes the table of contents
assigns (see :mod:`quaydoc.toc` and :mod:`quaydoc.slugs`).  That agreement is
what makes every ``#fragment`` on a rendered page resolvable.
"""

from __future__ import annotations

from dataclasses import dataclass

from quaydoc.slugs import anchor_of

EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "ftp://", "//")


def target_for(title):
    """Return the ``#fragment`` a link to a heading titled ``title`` uses."""
    return "#" + anchor_of(title)


def normalize_title(title):
    """Normalise a title for index lookups (case + whitespace folding)."""
    return " ".join(str(title).lower().split())


def looks_external(url):
    return url.startswith(EXTERNAL_PREFIXES)


@dataclass
class LinkResult:
    """Outcome of resolving one internal reference."""

    url: str
    label: str
    ok: bool
    error: str = ""
    resolved_fragment: str = ""


class LinkResolver:
    """Resolves page titles, heading titles and relative paths to URLs.

    ``pages`` is an iterable of page objects exposing ``url``, ``title`` and
    ``rel_posix``; ``heading_index`` maps a :func:`normalize_title`-ed heading
    title to the URL of the page containing it.  Resolution is lenient:
    unknown targets resolve to a best-guess URL with ``ok=False`` so the
    rendered page can mark them and the checker can report them.
    """

    def __init__(self, pages, heading_index):
        self._pages = {p.rel_posix: p for p in pages}
        self._by_url = {p.url: p for p in pages}
        self._titles = {}
        for page in pages:
            key = normalize_title(page.title)
            self._titles.setdefault(key, []).append(page)
        self._headings = dict(heading_index)

    def _title_page(self, title):
        matches = self._titles.get(normalize_title(title))
        return matches[0] if matches else None

    def resolve(self, raw, from_page):
        """Resolve a ``[[...]]`` target relative to ``from_page``."""
        raw = str(raw).strip()
        fragment = ""
        if "#" in raw:
            head, _, fragment = raw.partition("#")
            head = head.strip()
        else:
            head = raw

        if not head:
            return LinkResult("#" + fragment, raw, True)

        if _looks_like_path(head):
            return self._resolve_path(head, fragment, from_page)

        page = self._title_page(head)
        if page is not None:
            return LinkResult(page.url, raw, True, resolved_fragment=fragment)

        heading = self._headings.get(normalize_title(head))
        if heading is not None:
            url = heading + target_for(head)
            return LinkResult(url, raw, True)

        guess = self._solve_guess(head, from_page)
        return LinkResult(
            guess, raw, False,
            error=f"no page or heading titled {head!r}", resolved_fragment=fragment)

    def resolve_path(self, raw, from_page):
        """Resolve a relative file path (link or image source)."""
        if looks_external(raw) or raw.startswith("#"):
            return LinkResult(raw, raw, True)
        head, _, fragment = raw.partition("#")
        return self._resolve_path(head, fragment, from_page)

    def _resolve_path(self, head, fragment, from_page):
        import posixpath
        base = posixpath.dirname(str(getattr(from_page, "rel_posix", "")))
        candidate = posixpath.normpath(posixpath.join(base, head))
        page = self._pages.get(candidate)
        if page is not None:
            url = page.url + (("#" + fragment) if fragment else "")
            return LinkResult(url, head, True, resolved_fragment=fragment)
        return LinkResult(head, head, False,
                          error=f"no page at {head!r}",
                          resolved_fragment=fragment)

    def _solve_guess(self, head, from_page):
        import posixpath
        base = posixpath.dirname(str(getattr(from_page, "rel_posix", "")))
        for suffix in ("", ".qd", ".md"):
            candidate = posixpath.normpath(
                posixpath.join(base, head + suffix))
            page = self._pages.get(candidate)
            if page is not None:
                return page.url
        return "#" + anchor_of(head)


def _looks_like_path(target):
    return "/" in target or target.endswith((".qd", ".md", ".markdown",
                                            ".mdown", ".html"))

def collect_refs(blocks, out=None):
    """All ``[[...]]`` targets (and plain link URLs) named by a page."""
    if out is None:
        out = set()
    from quaydoc.nodes import (
        Admonition, BlockQuote, ExtLink, List, ListItem, Paragraph, RefLink)
    for block in blocks:
        if isinstance(block, (BlockQuote, Admonition)):
            collect_refs(block.children, out)
        elif isinstance(block, List):
            for item in block.items:
                collect_refs(item.blocks, out)
        elif isinstance(block, Paragraph):
            for node in block.inlines:
                if isinstance(node, RefLink):
                    out.add(node.target)
                elif isinstance(node, ExtLink):
                    out.add(node.url)
    return out


def unresolved_refs(page, resolver):
    """(target, error) pairs whose resolution failed for ``page``."""
    out = []
    for target in sorted(collect_refs(page.blocks)):
        result = resolver.resolve(target, page)
        if not result.ok:
            out.append((target, result.error))
    return out
