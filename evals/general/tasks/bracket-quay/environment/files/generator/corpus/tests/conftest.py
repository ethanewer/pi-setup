"""Shared fixtures for the quaydoc test suite.

``mini_site`` builds a real site from a dict of ``rel_path -> source`` files
(plus an optional ``quaydoc.toml`` entry) and returns ``(site, outdir)`` so
tests can assert on rendered pages, the checker, the search index and the
feed in one go.
"""

from __future__ import annotations

import os

import pytest

from quaydoc.check import Checker
from quaydoc.config import load_config
from quaydoc.site import Site


def write_tree(tmp_path, files, config=None, subdir="docs"):
    root = tmp_path / subdir
    root.mkdir(parents=True, exist_ok=True)
    if config is not None:
        (root / "quaydoc.toml").write_text(config, encoding="utf-8")
    for rel, body in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
    return root


@pytest.fixture
def build_site(tmp_path):
    """Factory: build a site from {rel: source} files + optional config."""

    def _build(files, config=None):
        root = write_tree(tmp_path, files, config)
        site = Site(str(root), load_config(str(root))).load()
        outdir = str(tmp_path / "out")
        site.build(outdir=outdir)
        return site, outdir

    return _build


@pytest.fixture
def check_built():
    """Run the checker over a built outdir and return the issues."""

    def _check(outdir, full=False):
        checker = Checker(outdir)
        return (checker.all_issues() if full else checker.check())

    return _check


def read_page(outdir, url):
    """Read a rendered page's HTML from a pretty-URL site by URL."""
    path = url.strip("/")
    if not path:
        path = "index.html"
    elif url.endswith("/"):
        path = path + "/index.html"
    else:
        path = path + ".html"
    with open(os.path.join(outdir, path), encoding="utf-8") as fh:
        return fh.read()


@pytest.fixture
def page_html():
    return lambda outdir, url: read_page(outdir, url)
