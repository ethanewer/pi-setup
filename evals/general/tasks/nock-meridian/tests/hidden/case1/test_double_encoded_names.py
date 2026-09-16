"""Hidden case 1: Link.filename single-component invariance on double-encoded
bytes the upstream regression test does not use.

The upstream test covers a double-encoded '/' (%252F). These cases drive other
double-encoded bytes -- '+', space, '#', '%' -- plus a mixed escaped path, and
assert BOTH the single-component invariant AND the exact once-decoded value,
so a tree that merely strips the second decode but keeps corrupting names (or
that stops decoding entirely) fails here.
"""
from __future__ import annotations

import posixpath

import pytest

from pip._internal.models.link import Link

URLS = [
    # A name that must survive the derivation as the literal once-decoded
    # escape, not as the decoded character it encodes.
    "https://example.com/pkg-1.0%252Bbuild7.whl",
    "https://example.com/spaces%2520in%2520name.tar.gz",
    "https://example.com/a%2523b.zip",
    "https://example.com/x%2525y.whl",
    "https://example.com/x%252Fy-1.0.tar.gz",
    "https://example.com/v1%252Fpkg-0.1.tar.gz",
]


@pytest.mark.parametrize("url", URLS)
def test_double_encoded_byte_stays_one_component(url: str) -> None:
    name = Link(url).filename
    assert not posixpath.isabs(name)
    assert posixpath.basename(name) == name
    assert "/" not in name


def test_exact_once_decoded_values() -> None:
    assert (
        Link("https://example.com/pkg-1.0%252Bbuild7.whl").filename
        == "pkg-1.0%2Bbuild7.whl"
    )
    assert (
        Link("https://example.com/spaces%2520in%2520name.tar.gz").filename
        == "spaces%20in%20name.tar.gz"
    )
    assert Link("https://example.com/a%2523b.zip").filename == "a%23b.zip"
    assert Link("https://example.com/x%2525y.whl").filename == "x%25y.whl"
    assert (
        Link("https://example.com/v1%252Fpkg-0.1.tar.gz").filename
        == "v1%2Fpkg-0.1.tar.gz"
    )


def test_single_encode_still_decodes_exactly_once() -> None:
    # A name encoded once decodes once: the escape is consumed, not kept, and
    # a normal name passes through untouched.
    assert Link("https://example.com/a%2520b.whl").filename == "a%20b.whl"
    assert Link("https://example.com/sp%2Becial.whl").filename == "sp+ecial.whl"
    assert Link("https://example.com/page%231.html").filename == "page#1.html"
    assert Link("https://example.com/path/wheel.whl").filename == "wheel.whl"