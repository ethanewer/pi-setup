"""Tests for the remaining modules: markup, urls, textio, meta, highlight,
lint, redirects, nav, migration, quality, versions, cache and stats."""

import json

import pytest

from quaydoc import markup, nav, redirects, textio, urls
from quaydoc import highlight, util
from quaydoc.config import load_config
from quaydoc.lint import check_references, lint_tree
from quaydoc.meta import parse_date, parse_frontmatter
from quaydoc.site import Site, BuildCache
from quaydoc import migration


def test_markup_plaintext():
    from quaydoc.parser import parse_document
    doc = parse_document("hello **bold** and `code` here\n")
    assert "hello bold and code here" in markup.plaintext_blocks(doc.blocks)


def test_markup_summary_shortens():
    from quaydoc.parser import parse_document
    doc = parse_document("word " * 200 + "\n")
    summary = markup.summary(doc.blocks, 40)
    assert len(summary) <= 45
    assert summary.endswith("…")


def test_urls_pretty_vs_flat():
    assert urls.page_url("guide/install", True) == "/guide/install/"
    assert urls.page_url("guide/install", False) == "/guide/install.html"
    assert urls.page_url("index", True) == "/"


def test_urls_output_rel():
    assert urls.output_rel("guide/x", True) == "guide/x/index.html"
    assert urls.output_rel("guide/x", False) == "guide/x.html"
    assert urls.output_rel("index", True) == "index.html"


def test_urls_canonical():
    assert urls.canonical_url("/g/", "https://x.test") == "https://x.test/g/"


def test_urls_version_discovery(tmp_path):
    (tmp_path / "v12").mkdir()
    (tmp_path / "vlatest").mkdir()
    (tmp_path / "nope").mkdir()
    assert sorted(urls.discover_versions(str(tmp_path))) == ["v12", "vlatest"]


def test_version_url():
    assert urls.version_url("v12", True, "guide/x") == "/v12/guide/x/"
    assert urls.version_url("vlatest", True, "guide/x") == "/guide/x/"


def test_textio_bom(tmp_path):
    import codecs
    tmp = tmp_path / "doc.qd"
    tmp.write_bytes(codecs.BOM_UTF8 + "héllo\n".encode("utf-8"))
    assert textio.read_utf8_text(str(tmp)) == "héllo\n"


def test_textio_newlines(tmp_path):
    tmp = tmp_path / "d.qd"
    tmp.write_bytes(b"a\r\nb\rc\n")
    assert textio.read_utf8_text(str(tmp)) == "a\nb\nc\n"


def test_frontmatter_types():
    data, body = parse_frontmatter(
        "---\ntitle: X\ncount: 3\nflag: true\ntags: [a, b]\n---\nbody\n")
    assert data == {"title": "X", "count": 3, "flag": True, "tags": ["a", "b"]}
    assert body == "body\n"


def test_parse_date_iso():
    from datetime import date
    assert parse_date("2025-01-02") == date(2025, 1, 2)
    assert parse_date("nope") is None


def test_highlight_python():
    out = highlight.highlight("def f(): return 1", "python")
    assert "tok-keyword" in out


def test_highlight_unknown_lang_escaped():
    out = highlight.highlight("<b>&", "zorg")
    assert "&lt;b&gt;&amp;" in out


def test_highlight_guess_lang():
    assert highlight.guess_lang("def f(): import os") == "python"
    assert highlight.guess_lang("plain text") == "text"


def test_util_helpers():
    assert util.unique([1, 2, 1, 3]) == [1, 2, 3]
    assert util.flatten([[1], [2, 3]]) == [1, 2, 3]
    assert util.collapse_ws("  a   b\n c ") == "a b c"
    assert util.human_bytes(2048) == "2.0 KB"


def test_util_write_text_atomic(tmp_path):
    target = tmp_path / "sub" / "f.txt"
    util.write_text(str(target), "hi")
    assert target.read_text(encoding="utf-8") == "hi"


def test_util_json_roundtrip(tmp_path):
    path = tmp_path / "j.json"
    util.write_json(str(path), {"a": 1})
    assert util.read_json(str(path)) == {"a": 1}
    assert util.read_json(str(tmp_path / "missing.json")) is None


def test_lint_finds_unresolved_ref(tmp_path):
    root = tmp_path / "docs"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\ntitle: H\n---\nsee [[Nothing]]\n", encoding="utf-8")
    config = load_config(str(root))
    findings = check_references(str(root), config)
    assert any("Nothing" in f.message for f in findings)


def test_lint_trailing_ws(tmp_path):
    root = tmp_path / "docs"
    root.mkdir()
    (root / "index.qd").write_text("---\ntitle: H\n---\nline \n",
                                   encoding="utf-8")
    findings = lint_tree(str(root), load_config(str(root)))
    assert any(f.code == "trailing-whitespace" for f in findings)


def test_redirect_pairs(tmp_path):
    from quaydoc.site import Site
    root = tmp_path / "d"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\ntitle: New\nredirect_from: ['/old/']\n---\nbody\n",
        encoding="utf-8")
    site = Site(str(root), load_config(str(root))).load()
    assert redirects.collect_redirects(site.pages) == [("/old/", "/")]


def test_redirect_html_meta():
    out = redirects.redirect_html("/new/")
    assert 'content="0; url=/new/"' in out


def test_nav_rows(tmp_path):
    root = tmp_path / "d"
    root.mkdir()
    (root / "b.qd").write_text("---\ntitle: B\norder: 2\n---\nx\n",
                               encoding="utf-8")
    (root / "a.qd").write_text("---\ntitle: A\norder: 1\n---\nx\n",
                               encoding="utf-8")
    site = Site(str(root), load_config(str(root))).load()
    rows = nav.build_nav(site)
    assert [r.title for r in rows] == ["A", "B"]


def test_nav_prev_next(tmp_path):
    root = tmp_path / "d"
    root.mkdir()
    (root / "a.qd").write_text("---\ntitle: A\norder: 1\n---\nx\n",
                               encoding="utf-8")
    (root / "b.qd").write_text("---\ntitle: B\norder: 2\n---\nx\n",
                               encoding="utf-8")
    site = Site(str(root), load_config(str(root))).load()
    nodes = nav.linearize(site.pages)
    assert nodes[0].next_page.title == "B"
    assert nodes[1].prev_page.title == "A"
    assert "Next" in nav.next_link(nodes[0])


def test_migration_dry_run(tmp_path):
    root = tmp_path / "d"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\nissued: 2025-01-01\n---\nbody\n", encoding="utf-8")
    config = load_config(str(root))
    records = migration.migrate_tree(str(root), config, dry_run=True)
    assert records
    assert "issued" in open(root / "index.qd", encoding="utf-8").read()


def test_migration_apply(tmp_path):
    root = tmp_path / "d"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\nissued: 2025-01-01\n---\nbody\n", encoding="utf-8")
    config = load_config(str(root))
    migration.migrate_tree(str(root), config)
    assert "date: 2025-01-01" in open(root / "index.qd",
                                      encoding="utf-8").read()


def test_quality_finds_todo(tmp_path):
    root = tmp_path / "d"
    root.mkdir()
    (root / "index.qd").write_text("---\ntitle: H\n---\nTODO fix me\n",
                                   encoding="utf-8")
    from quaydoc.lint import quality_check
    findings = quality_check(str(root), load_config(str(root)))
    assert any(f.code == "todo" for f in findings)


def test_build_cache(tmp_path):
    cache = BuildCache(str(tmp_path))
    assert cache.is_current("a.html", "render1") is False
    cache.record("a.html", "render1")
    assert cache.is_current("a.html", "render1") is True
    assert cache.is_current("a.html", "render2") is False
    cache.save()
    reloaded = BuildCache(str(tmp_path))
    assert reloaded.is_current("a.html", "render1") is True


def test_stats_report():
    from quaydoc.stats import BuildStats
    stats = BuildStats()
    stats.add_page(10, 100)
    report = stats.report()
    assert "1 page" in report


def test_archive_dir(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.txt").write_text("hello", encoding="utf-8")
    dest = str(tmp_path / "out.tar.gz")
    created = util.archive_dir(str(src), dest)
    import tarfile
    assert tarfile.is_tarfile(created)
    with tarfile.open(created, "r:gz") as tar:
        assert "a.txt" in tar.getnames()
