"""Link resolution and fragment-target tests."""

import pytest

from quaydoc.links import LinkResolver, normalize_title, target_for


def test_target_for_prefixes_hash():
    assert target_for("Getting started") == "#getting-started"


def test_target_for_canonical_ampersand():
    # The link side of the pipeline spells & titles without the ampersand:
    # this is the shared contract that every id-producing module must match.
    assert target_for("Setup & First Steps") == "#setup-first-steps"
    assert target_for("R & D pipeline") == "#r-d-pipeline"


def test_target_for_canonical_colon():
    assert target_for("FAQ: v2") == "#faq-v2"


def test_target_for_empty_falls_back():
    assert target_for("!!!") == "#section"


def test_normalize_title():
    assert normalize_title("  Setup & First  Steps ") == "setup & first steps"


class _Page:
    def __init__(self, slug, url, title):
        self.rel_posix = slug
        self.url = url
        self.title = title


def make_resolver():
    pages = [
        _Page("index", "/", "Home"),
        _Page("guide/install", "/guide/install/", "Installation"),
    ]
    headings = {
        "setup & first steps": "/guide/install/",
        "faq: v2": "/",
    }
    return LinkResolver(pages, headings)


def test_resolve_page_title():
    r = make_resolver()
    result = r.resolve("Installation", _Page("x", "/x/", "X"))
    assert result.ok
    assert result.url == "/guide/install/"


def test_resolve_heading_title_fragment_is_canonical():
    r = make_resolver()
    result = r.resolve("Setup & First Steps", _Page("x", "/x/", "X"))
    assert result.ok
    assert result.url == "/guide/install/#setup-first-steps"


def test_resolve_colon_heading():
    r = make_resolver()
    result = r.resolve("FAQ: v2", _Page("x", "/x/", "X"))
    assert result.url == "/#faq-v2"


def test_resolve_unknown_title_reports_failure():
    r = make_resolver()
    result = r.resolve("No Such Thing", _Page("x", "/x/", "X"))
    assert not result.ok
    assert result.error


def test_resolve_relative_path():
    r = make_resolver()
    result = r.resolve("../guide/install", _Page("guide/x", "guide/x", "X"))
    assert result.ok
    assert result.url == "/guide/install/"


def test_resolve_missing_path_fails():
    r = make_resolver()
    result = r.resolve("guide/nope", _Page("x", "/x/", "X"))
    assert not result.ok


def test_resolve_path_with_fragment():
    r = make_resolver()
    result = r.resolve("guide/install#intro", _Page("x", "/x/", "X"))
    assert result.url == "/guide/install/#intro"


def test_external_links_pass_through():
    r = make_resolver()
    result = r.resolve_path("https://example.org/x", _Page("x", "/x/", "X"))
    assert result.ok
    assert result.url == "https://example.org/x"
