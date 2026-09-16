"""Page model: one source document and its rendered form."""

from __future__ import annotations

import os
from pathlib import Path

from quaydoc import meta as _meta
from quaydoc import parser, urls
from quaydoc.errors import SourceError
from quaydoc.toc import AnchorMap
from quaydoc.util import is_within, read_text


class Page:
    """A single documentation source file plus everything derived from it."""

    def __init__(self, source, root, config):
        self.source = Path(source)
        self.root = Path(root)
        self.config = config
        self.rel_path = os.path.relpath(str(self.source), str(self.root))
        self.rel_posix = os.path.relpath(str(self.source), str(self.root)) \
            .replace(os.sep, "/")
        self.frontmatter = {}
        self.blocks = []
        self.headings = []
        self.warnings = []
        self.anchor_map = AnchorMap()
        self.sections = []
        self.html_content = ""
        self.footnote_numbers = {}
        self.section_numbers = {}
        self._loaded = False

    # -- parsing ------------------------------------------------------------

    def load(self):
        """Read and parse the source file, populating page metadata."""
        text = read_text(self.source)
        doc = parser.parse_document(
            text, str(self.rel_posix), includer=self._includer)
        self.frontmatter = doc.frontmatter
        self.blocks = doc.blocks
        self.headings = doc.headings
        self.warnings = list(doc.warnings)
        self._loaded = True
        return self

    def _includer(self, include_path, source):
        """Load an included document relative to this page, root-bounded."""
        base = os.path.dirname(str(self.source))
        target = os.path.normpath(os.path.join(base, include_path))
        if is_within(target, str(self.root)):
            if os.path.isfile(target):
                return read_text(target)
            raise SourceError(f"{source}: include {include_path!r} not found")
        raise SourceError(
            f"{source}: include {include_path!r} escapes the documentation "
            "root (blocked)")

    # -- metadata -----------------------------------------------------------

    @property
    def title(self):
        if self.frontmatter.get("title"):
            return str(self.frontmatter["title"])
        for level, text in self.headings:
            return text
        return urls.page_posix(self.rel_posix).replace("/", " ").strip(" /") \
            .title() or "Untitled"

    @property
    def nav_title(self):
        return str(self.frontmatter.get("nav_title") or self.title)

    @property
    def description(self):
        return str(self.frontmatter.get("description") or "")

    @property
    def order(self):
        try:
            return int(self.frontmatter.get("order", 100000))
        except (TypeError, ValueError):
            return 100000

    @property
    def date(self):
        return self.frontmatter.get("date")

    @property
    def draft(self):
        return bool(self.frontmatter.get("draft", False))

    @property
    def tags(self):
        tags = self.frontmatter.get("tags", [])
        return tags if isinstance(tags, list) else [tags]

    @property
    def permalink(self):
        return self.frontmatter.get("permalink")

    @property
    def redirect_from(self):
        value = self.frontmatter.get("redirect_from")
        if value is None:
            return []
        return value if isinstance(value, list) else [value]

    @property
    def show_toc(self):
        value = self.frontmatter.get("toc", self.config.toc)
        return bool(value) if isinstance(value, bool) else bool(self.config.toc)

    @property
    def slug(self):
        return urls.page_posix(self.rel_posix)

    @property
    def url(self):
        if self.permalink:
            return self.permalink if self.permalink.startswith("/") \
                else "/" + self.permalink
        return urls.page_url(self.slug, self.config.pretty_urls)

    @property
    def aliases(self):
        value = self.frontmatter.get("aliases", [])
        return value if isinstance(value, list) else []

    @property
    def out_rel(self):
        return urls.output_rel(self.slug, self.config.pretty_urls)

    def out_path(self, outdir):
        return os.path.normpath(os.path.join(outdir, self.out_rel))

    @property
    def current_anchor(self):
        """Anchor of the active heading, when rendered with a TOC panel."""
        return None

    def __repr__(self):
        return f"<Page {self.rel_posix!r} -> {self.url!r}>"
