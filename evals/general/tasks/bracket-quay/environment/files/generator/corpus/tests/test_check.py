"""Integrity checker tests."""

import os

import pytest

from quaydoc.check import Checker, Issue


def write_site(tmp_path, pages):
    out = tmp_path / "site"
    for rel, body in pages.items():
        p = out / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    return str(out)


GOOD = {
    "index.html": (
        '<!DOCTYPE html><html><head><title>x</title></head><body>'
        '<h2 id="intro">Intro</h2>'
        '<a href="#intro">jump</a>'
        '<a href="/other/">other page</a>'
        '<img src="/assets/logo.png" alt="l">'
        "</body></html>"),
    "other/index.html": '<html><body><h2 id="part">Part</h2></body></html>',
    "assets/logo.png": "PNG",
}


def test_clean_site_pass(tmp_path):
    out = write_site(tmp_path, GOOD)
    assert Checker(out).check() == []


def test_broken_fragment_detected(tmp_path):
    pages = dict(GOOD)
    pages["index.html"] = pages["index.html"].replace(
        '<a href="#intro">', '<a href="#missing">')
    out = write_site(tmp_path, pages)
    issues = Checker(out).check()
    assert any(i.code == "broken-fragment" for i in issues)


def test_cross_page_fragment_detected(tmp_path):
    pages = dict(GOOD)
    pages["index.html"] = pages["index.html"].replace(
        '<a href="/other/">', '<a href="/other/#nope">')
    out = write_site(tmp_path, pages)
    issues = Checker(out).check()
    assert any(i.code == "broken-fragment" for i in issues)


def test_missing_page_detected(tmp_path):
    pages = dict(GOOD)
    pages["index.html"] = pages["index.html"].replace(
        '<a href="/other/">', '<a href="/gone/">')
    out = write_site(tmp_path, pages)
    issues = Checker(out).check()
    assert any(i.code == "missing-page" for i in issues)


def test_missing_image_detected(tmp_path):
    pages = dict(GOOD)
    pages["index.html"] = pages["index.html"].replace(
        '/assets/logo.png', '/assets/nope.png')
    out = write_site(tmp_path, pages)
    issues = Checker(out).check()
    assert any(i.code == "missing-image" for i in issues)


def test_duplicate_id_detected(tmp_path):
    pages = dict(GOOD)
    pages["index.html"] = pages["index.html"].replace(
        '<h2 id="intro">', '<h2 id="intro">dup<h3 id="intro">')
    out = write_site(tmp_path, pages)
    issues = Checker(out).check()
    assert any(i.code == "duplicate-id" for i in issues)


def test_external_links_ignored(tmp_path):
    pages = dict(GOOD)
    pages["index.html"] = pages["index.html"].replace(
        '<a href="/other/">', '<a href="https://x.test/">')
    out = write_site(tmp_path, pages)
    assert Checker(out).check() == []


def test_empty_page_warning(tmp_path):
    pages = {"empty/index.html": "<html><body></body></html>"}
    out = write_site(tmp_path, pages)
    issues = Checker(out).check()
    assert any(i.code == "empty-page" for i in issues)


def test_bad_encoding(tmp_path):
    out = write_site(tmp_path, {"bad/index.html": ""})
    with open(os.path.join(out, "bad", "index.html"), "wb") as fh:
        fh.write(b"\xff\xfe\x00bad")
    issues = Checker(out).encoding_issues()
    assert any(i.code == "bad-encoding" for i in issues)


def test_issue_render():
    issue = Issue("error", "broken-fragment", "nothing matches", "x.html")
    assert issue.render().startswith("error")


def test_list_codes():
    codes = Checker.list_codes()
    assert "broken-fragment" in codes
