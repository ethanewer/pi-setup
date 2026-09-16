"""Inline markup parser tests."""

import pytest

from quaydoc import inline
from quaydoc.nodes import Bold, CodeSpan, ExtLink, FootnoteRef, Image, RefLink, Text


def par(text):
    return inline.parse_inline(text)


def text_of(nodes):
    return inline.plain_text(nodes)


def test_plain_text_passthrough():
    nodes = par("hello world")
    assert len(nodes) == 1
    assert isinstance(nodes[0], Text)
    assert nodes[0].text == "hello world"


def test_bold():
    nodes = par("a **b** c")
    assert nodes[1].children[0].text == "b"


def test_bold_untwined():
    assert isinstance(par("**open")[0], Text)


def test_code_span():
    nodes = par("use `print(1)` here")
    assert isinstance(nodes[1], CodeSpan)
    assert nodes[1].code == "print(1)"


def test_ref_link():
    nodes = par("see [[Setup & First Steps|the setup page]]")
    link = nodes[1]
    assert isinstance(link, RefLink)
    assert link.target == "Setup & First Steps"
    assert link.label == "the setup page"


def test_ref_link_default_label():
    link = par("[[Installation]]")[0]
    assert link.target == link.label == "Installation"


def test_external_link():
    link = par("[docs](https://example.org)")[0]
    assert isinstance(link, ExtLink)
    assert link.url == "https://example.org"


def test_relative_link():
    link = par("[other](../guide/other.qd)")[0]
    assert link.url == "../guide/other.qd"


def test_image():
    img = par("![alt text](images/logo.png)")[0]
    assert isinstance(img, Image)
    assert img.alt == "alt text"


def test_image_with_title():
    img = par('![logo](images/logo.png "Logo")')[0]
    assert img.title == "Logo"


def test_footnote_ref():
    node = par("text[^n]more")[1]
    assert isinstance(node, FootnoteRef)
    assert node.name == "n"


def test_escapes():
    assert text_of(par(r"literal \* star")) == "literal * star"


def test_malformed_link_is_text():
    nodes = par("[unclosed")
    assert isinstance(nodes[0], Text)


def test_plain_text_merges():
    assert text_of(par("**bold** and `code` and [[Ref|label]]")) == \
        "bold and code and label"


def test_emoji_expand():
    assert "🙂" in inline.expand_emoji("hello :smile:")
    assert ":unknown:" in inline.expand_emoji("x :unknown: y")
