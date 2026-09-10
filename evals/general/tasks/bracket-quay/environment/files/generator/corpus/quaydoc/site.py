"""Site assembly: pages in, a validated static site out."""

from __future__ import annotations

import os

from quaydoc import __version__
from quaydoc import blocks, check as _check, finder, html
from quaydoc import nav, redirects, rss, search, snippet as _snippet
from quaydoc import sitemap, theme, toc as _toc, toc as _sections
from quaydoc.config import load_config
from quaydoc.links import LinkResolver, normalize_title
from quaydoc.page import Page
from quaydoc.stats import BuildStats
from quaydoc.template import Template
from quaydoc.util import ensure_dir, write_text


class Site:
    """A loaded documentation tree, ready to build."""

    def __init__(self, root, config=None, outdir=None):
        self.root = os.path.abspath(root)
        self.config = config if config is not None else load_config(self.root)
        self.pages = []
        self.by_url = {}
        self.heading_index = {}     # normalized title -> page url
        self.resolver = None
        self.templates = {}
        self.stats = BuildStats()
        self.version = __version__

    # -- loading ------------------------------------------------------------

    def load(self):
        """Discover, parse and index every non-draft page."""
        for source in finder.find_docs(self.root, self.config):
            page = Page(source, self.root, self.config).load()
            if page.draft:
                continue
            page.sections = _toc.build_sections(page.headings)
            page.anchor_map.assign(page.sections)
            if self.config.number_sections:
                flat = _flatten_sections(page.sections)
                numbered = _sections.number_lines(flat)
                page.section_numbers = {
                    title: display.split(" ", 1)[0]
                    for (_, display, _), (_, title, _) in
                    zip(numbered, flat)}
            else:
                page.section_numbers = {}
            for level, title in page.headings:
                key = normalize_title(title)
                if key in self.heading_index:
                    page.warnings.append(
                        f"{page.rel_posix}: heading title {title!r} is not "
                        "unique across the site")
                else:
                    self.heading_index[key] = page.url
            if page.url in self.by_url:
                page.warnings.append(
                    f"{page.rel_posix}: duplicate route {page.url!r}")
            self.by_url[page.url] = page
            self.pages.append(page)
        self.pages.sort(key=lambda p: (p.order, p.slug))
        self.resolver = LinkResolver(self.pages, self.heading_index)
        self.templates = {
            name: Template(body, name) for name, body in theme.TEMPLATES.items()
        }
        self._load_user_theme()
        return self

    def _load_user_theme(self):
        """Overlay templates from a configured theme directory (if any)."""
        theme_dir = getattr(self.config, "theme", None)
        if not theme_dir:
            return
        templates_dir = os.path.join(self.root, theme_dir, "templates")
        if os.path.isdir(templates_dir):
            for name in sorted(os.listdir(templates_dir)):
                if name.endswith(".html"):
                    with open(os.path.join(templates_dir, name),
                              encoding="utf-8") as fh:
                        body = fh.read()
                    self.templates[name] = Template(body, name)

    # -- building -----------------------------------------------------------

    def build(self, outdir=None, archive=None):
        """Render every page into ``outdir`` (or the configured output path).

        Returns the :class:`BuildStats` record for the build.
        """
        self.stats = BuildStats()
        out = os.path.abspath(outdir) if outdir else \
            os.path.abspath(self.config.output_path)
        ensure_dir(out)

        for page in self.pages:
            ctx = blocks.RenderContext(page, self, self.resolver)
            page.html_content = blocks.render_blocks(page.blocks, ctx)
            page.html_content += blocks.render_footnotes(page.blocks, ctx)
            ctx.page.footnote_numbers = page.footnote_numbers
            page.html = html.render_page_html(page, self)
            if self.config.postprocess:
                page.html = html.postprocess(
                    page.html,
                    new_tab=getattr(self.config, "external_links_new_tab",
                                    False))
                page.html = html.ensure_trailing_newline(page.html)
            target = page.out_path(out)
            write_text(target, page.html)
            words = len(page.html_content.split())
            self.stats.add_page(words, len(page.html.encode("utf-8")))

        theme.write_assets(out)
        self._copy_static(out)

        if self.config.snippet:
            written = _snippet.write_snippets(self, out)
            self.stats.snippet_count = written

        if self.config.number_sections:
            pass  # numbering is applied at render time via page.section_numbers

        if redirects.collect_redirects(self.pages):
            written = redirects.write_redirects(
                out, redirects.collect_redirects(self.pages),
                self.config.pretty_urls)
            self.stats.redirect_count = written

        if self.config.search:
            index = search.build_index(self.pages)
            search.write_index(out, index)
            search.write_search_page(out, self)

        self._write(out, "headings.json", _headings_manifest(self.pages))
        self._write(out, "build.json", _build_manifest(self, out))
        self._write(out, "sitemap.xml",
                    sitemap.build_sitemap(self.pages, self.config.base_url))
        if self.config.rss:
            self._write(out, "feed.xml", rss.build_feed(self.pages, self.config))

        if archive:
            from quaydoc.util import archive_dir
            self.stats.archive_path = archive_dir(out, archive)

        if self.config.build_cache:
            cache = BuildCache(out)
            for page in self.pages:
                cache.record(page.out_rel, page.html)
            cache.save()

        self.stats.phase("render", self.stats.elapsed)
        return self.stats

    def _write(self, outdir, name, text):
        write_text(os.path.join(outdir, name), text)

    # -- derived views -------------------------------------------------------

    def nav_html(self, current_url):
        return nav.nav_html(self, current_url)

    def check(self, outdir):
        """Run the integrity checker over a build of this site."""
        return _check.Checker(outdir).check()

    def __repr__(self):
        return f"<Site {self.root!r} pages={len(self.pages)}>"

    def _copy_static(self, outdir):
        """Copy a ``static/`` directory next to the docs root into output."""
        static_src = os.path.join(self.root, "static")
        if not os.path.isdir(static_src):
            return 0
        copied = 0
        for dirpath, dirnames, filenames in os.walk(static_src):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for fname in sorted(filenames):
                if fname.startswith("."):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fname),
                                      static_src)
                dest = os.path.join(outdir, rel)
                ensure_dir(os.path.dirname(dest))
                with open(os.path.join(dirpath, fname), "rb") as fh:
                    data = fh.read()
                with open(dest, "wb") as fh:
                    fh.write(data)
                copied += 1
        return copied


def _flatten_sections(sections):
    """Flatten a section forest to ``(level, title, anchor)`` triples."""
    out = []
    for section in sections:
        out.append((section.level, section.title, section.anchor))
        out.extend(_flatten_sections(section.children))
    return out



def _iter_sections(sections):
    """Yield Section objects of a forest (objects, not triples)."""
    for section in sections:
        yield section
        yield from _iter_sections(section.children)


def _headings_manifest(pages):
    """A JSON inventory of every heading anchor shipped in the site."""
    import json
    entries = []
    for page in pages:
        for section in _iter_sections(page.sections):
            entries.append({
                "page": page.url,
                "title": section.title,
                "anchor": section.anchor,
                "level": section.level,
            })
    return json.dumps(entries, indent=1, ensure_ascii=False)


def _build_manifest(site, outdir):
    """Metadata about a build (version, page list, timings)."""
    import json
    import time
    return json.dumps({
        "generator": "quaydoc/" + site.version,
        "pages": [p.url for p in site.pages],
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "output": outdir,
    }, indent=1)





import json
import os

from quaydoc.util import read_text, sha256_hex, write_text

CACHE_FILE = ".quaydoc-cache.json"


class BuildCache:
    """Digest-based cache of one output directory."""

    def __init__(self, outdir, enabled=True):
        self.outdir = outdir
        self.path = os.path.join(outdir, CACHE_FILE)
        self.enabled = enabled
        self.items = {}
        if enabled and os.path.isfile(self.path):
            try:
                data = json.loads(read_text(self.path))
                if isinstance(data, dict):
                    self.items = {str(k): str(v) for k, v in data.items()}
            except (ValueError, OSError):
                self.items = {}

    def is_current(self, rel_path, rendered):
        if not self.enabled:
            return False
        return self.items.get(rel_path) == sha256_hex(rendered)

    def record(self, rel_path, rendered):
        if self.enabled:
            self.items[rel_path] = sha256_hex(rendered)

    def save(self):
        if not self.enabled:
            return
        write_text(self.path,
                   json.dumps(self.items, sort_keys=True, indent=1))
        try:
            os.chmod(self.path, 0o644)
        except OSError:
            pass


def prune_cache(outdir, keep_prefixes):
    """Drop cache entries whose keys are not under any ``keep_prefixes``."""
    cache = BuildCache(outdir)
    before = set(cache.items)
    cache.items = {
        key: value for key, value in cache.items.items()
        if any(key.startswith(prefix) for prefix in keep_prefixes)}
    cache.save()
    return len(before) - len(cache.items)

