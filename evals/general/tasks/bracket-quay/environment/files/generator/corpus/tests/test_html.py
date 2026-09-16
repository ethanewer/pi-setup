"""Page shell + postprocessing tests."""

from quaydoc import html
from quaydoc.util import escape_attr, escape_html


def test_escape_html():
    assert escape_html("<a & b>") == "&lt;a &amp; b&gt;"
    assert escape_html('quote " here') == "quote &quot; here"
    assert escape_html("it's") == "it&#39;s"


def test_escape_attr():
    assert escape_attr('a"b') == "a&quot;b"


def test_postprocess_external_link():
    before = '<p><a href="https://x.test/a">l</a></p>'
    after = html.postprocess(before)
    assert 'rel="noopener"' in after


def test_postprocess_keeps_internal_links():
    before = '<p><a href="/guide/">l</a></p>'
    after = html.postprocess(before)
    assert 'rel="noopener"' not in after


def test_postprocess_neutralises_javascript():
    before = '<a href="javascript:alert(1)">x</a>'
    assert 'javascript:' not in html.postprocess(before)


def test_postprocess_new_tab():
    after = html.postprocess('<a href="https://x.test/">l</a>', new_tab=True)
    assert 'target="_blank"' in after


def test_ensure_trailing_newline():
    assert html.ensure_trailing_newline("abc") == "abc\n"
    assert html.ensure_trailing_newline("abc\n") == "abc\n"


def test_render_page_has_shell(tmp_path):
    from quaydoc.config import load_config
    from quaydoc.site import Site
    root = tmp_path / "d"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\ntitle: Home\n---\nhello\n", encoding="utf-8")
    site = Site(str(root), load_config(str(root))).load()
    out = str(tmp_path / "o")
    site.build(outdir=out)
    page = site.pages[0]
    assert "<!DOCTYPE html>" in page.html
    assert "<title>Home · Docs</title>" in page.html
    assert "/assets/style.css" in page.html
