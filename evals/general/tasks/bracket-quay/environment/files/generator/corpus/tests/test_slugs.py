"""Canonical slug/anchor tests."""

import pytest

from quaydoc import slugs


@pytest.mark.parametrize("title,expected", [
    ("Hello World", "hello-world"),
    ("Hello, World!", "hello-world"),
    ("A & B / C", "a-b-c"),
    ("quick  start", "quick-start"),
    ("  padded  ", "padded"),
    ("UPPER CASE", "upper-case"),
    ("a--b", "a-b"),
    ("???", "section"),
    ("", "section"),
    ("Café Noir", "caf-noir"),
    ("1.2.3", "1-2-3"),
])
def test_anchor_of(title, expected):
    assert slugs.anchor_of(title) == expected


def test_fragment_of():
    assert slugs.fragment_of("Hello") == "#hello"


def test_file_slug_safe():
    assert "/" not in slugs.file_slug("a/b/c")
