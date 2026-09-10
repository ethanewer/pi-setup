"""Site build tests (end-to-end rendering of whole trees)."""

import json
import os

from quaydoc.config import load_config
from quaydoc.site import Site


FILES = {
    "index.qd": "---\ntitle: Home\norder: 10\n---\n## Intro\n\nBody here.\n",
    "guide/install.qd": (
        "---\ntitle: Installation\norder: 20\n---\n## Steps\n\nSee "
        "[[Home]] and the [guide index](../index.qd).\n"),
    "skip.qd": "---\ntitle: Draft\ndraft: true\n---\nsecret\n",
}


def build(tmp_path, files=None, config=None):
    root = tmp_path / "docs"
    for rel, body in (files or FILES).items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    if config:
        (root / "quaydoc.toml").write_text(config, encoding="utf-8")
    site = Site(str(root), load_config(str(root))).load()
    out = str(tmp_path / "out")
    stats = site.build(outdir=out)
    return site, out, stats


def test_build_writes_index(tmp_path):
    _, out, _ = build(tmp_path)
    assert os.path.isfile(os.path.join(out, "index.html"))
    assert os.path.isfile(os.path.join(out, "guide", "install", "index.html"))


def test_drafts_skipped(tmp_path):
    site, out, _ = build(tmp_path)
    assert len(site.pages) == 2
    assert all("Draft" != p.title for p in site.pages)


def test_pretty_urls(tmp_path):
    site, _, _ = build(tmp_path)
    assert {p.url for p in site.pages} >= {"/", "/guide/install/"}


def test_flat_urls(tmp_path):
    site, out, _ = build(tmp_path, config="[site]\npretty_urls = false\n")
    assert os.path.isfile(os.path.join(out, "guide", "install.html"))


def test_assets_written(tmp_path):
    _, out, _ = build(tmp_path)
    assert os.path.isfile(os.path.join(out, "assets", "style.css"))
    assert os.path.isfile(os.path.join(out, "assets", "quaydoc.js"))


def test_search_index_written(tmp_path):
    _, out, _ = build(tmp_path)
    entries = json.loads(open(os.path.join(out, "search_index.json"),
                              encoding="utf-8").read())
    titles = {e["title"] for e in entries}
    assert "Home" in titles and "Installation" in titles


def test_headings_manifest(tmp_path):
    _, out, _ = build(tmp_path)
    manifest = json.loads(open(os.path.join(out, "headings.json"),
                               encoding="utf-8").read())
    assert any(e["anchor"] == "intro" for e in manifest)


def test_build_manifest(tmp_path):
    _, out, _ = build(tmp_path)
    info = json.loads(open(os.path.join(out, "build.json"),
                           encoding="utf-8").read())
    assert info["generator"].startswith("quaydoc/")


def test_sitemap_and_feed(tmp_path):
    _, out, _ = build(tmp_path)
    assert os.path.isfile(os.path.join(out, "sitemap.xml"))
    assert os.path.isfile(os.path.join(out, "feed.xml"))


def test_order_sorts_pages(tmp_path):
    site, _, _ = build(tmp_path)
    assert site.pages[0].title == "Home"


def test_number_sections(tmp_path):
    site, out, _ = build(tmp_path,
                         config="[site]\nnumber_sections = true\n")
    assert site.pages[0].section_numbers.get("Intro") == "1"


def test_redirect_pages(tmp_path):
    site, out, _ = build(tmp_path)
    html = open(os.path.join(out, "guide", "install", "index.html"),
                encoding="utf-8").read()
    assert "Home" in html  # sidebar
