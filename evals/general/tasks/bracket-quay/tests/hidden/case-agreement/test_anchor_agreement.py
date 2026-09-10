"""Hidden case: the two sides of the anchor pipeline must agree.

The table-of-contents anchor computation (quaydoc.toc.AnchorMap.anchor_for)
and the reference-target computation (quaydoc.links.target_for) must
produce fragments that are IDENTICAL for every title — a rendered page is
only coherent when the id side and the link side speak the same spelling.
This battery uses titles the shipped suite never feeds the id side,
including ampersands, colons, punctuation and Unicode.
"""

import pytest

from quaydoc.links import target_for
from quaydoc.slugs import anchor_of, fragment_of
from quaydoc.toc import AnchorMap

CASES = [
    "Plain Heading",
    "Setup & First Steps",
    "FAQ: v2",
    "R & D pipeline",
    "A & B / C",
    "Hello, World!",
    "  padded  ",
    "Release 2.2: summary",
    "...",
    "",
    "Café Noir",
    "a--b",
    "x&y:z",
    "Notes on C++",
    "1.2.3",
]


@pytest.mark.parametrize("title", CASES)
def test_toc_anchor_matches_shared_slug(title):
    assert AnchorMap().anchor_for(title) == anchor_of(title)


@pytest.mark.parametrize("title", CASES)
def test_link_target_matches_shared_slug(title):
    assert target_for(title) == fragment_of(title)


@pytest.mark.parametrize("title", CASES)
def test_toc_anchor_matches_link_target(title):
    assert "#" + AnchorMap().anchor_for(title) == target_for(title)
