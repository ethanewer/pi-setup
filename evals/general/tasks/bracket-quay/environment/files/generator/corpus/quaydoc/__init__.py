"""quaydoc: a self-contained documentation site generator.

quaydoc turns a tree of plain-text source files (see ``README.md`` for the
markup) into a static HTML documentation site.  It is pure standard-library
Python: the lexer, parser, inline parser, slug/anchor logic, link resolver,
table of contents, renderers, template engine, theme, search index, sitemap,
Atom feed, checker, dev server and CLI all live in this package.

Typical use::

    from quaydoc.config import load_config
    from quaydoc.site import Site

    config = load_config("docs")
    site = Site("docs", config).load()
    site.build("site")
"""

__version__ = "0.9.0"
__all__ = ["__version__"]
