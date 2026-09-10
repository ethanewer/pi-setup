"""Table of contents and anchor-map tests.

Note: anchor agreement with the shared slugifier is exercised separately by
the rendering tests; these tests pin the tree-building and dedup behaviour.
"""

import pytest

from quaydoc import toc
from quaydoc.toc import AnchorMap, build_sections


def test_build_sections_nesting():
    sections = build_sections([(1, "A"), (2, "B"), (2, "C"), (3, "D")])
    assert [s.title for s in sections] == ["A"]
    assert [c.title for c in sections[0].children] == ["B", "C"]
    assert sections[0].children[1].children[0].title == "D"


def test_build_sections_multiple_roots():
    sections = build_sections([(2, "A"), (1, "B")])
    assert [s.title for s in sections] == ["A", "B"]


def test_anchor_basic():
    am = AnchorMap()
    assert am.anchor_for("Quick Start") == "quick-start"


def test_anchor_dedupe():
    am = AnchorMap()
    first = am.take("Notes")
    second = am.take("Notes")
    assert first == "notes"
    assert second == "notes-2"
    assert am.lookup("Notes") == "notes-2"


def test_assign_sets_anchors():
    am = AnchorMap()
    sections = build_sections([(2, "Intro"), (3, "Details")])
    am.assign(sections)
    assert sections[0].anchor == "intro"
    assert sections[0].children[0].anchor == "details"


def test_toc_html_structure():
    am = AnchorMap()
    sections = build_sections([(2, "Alpha"), (2, "Beta")])
    am.assign(sections)
    html = toc.toc_html(sections)
    assert html.count("<li>") == 2
    assert 'href="#alpha"' in html
    assert 'href="#beta"' in html


def test_toc_html_current_marked():
    am = AnchorMap()
    sections = build_sections([(2, "Alpha")])
    am.assign(sections)
    html = toc.toc_html(sections, current_anchor="alpha")
    assert 'class="current"' in html


def test_toc_html_nested():
    am = AnchorMap()
    sections = build_sections([(2, "A"), (3, "B")])
    am.assign(sections)
    html = toc.toc_html(sections)
    assert html.count("<ul") == 2


def test_section_numbering():
    from quaydoc.toc import number_lines
    numbered = number_lines([(1, "A", "a"), (2, "B", "b"), (2, "C", "c")])
    assert [n for _, n, _ in numbered] == ["1 A", "1.1 B", "1.2 C"]
