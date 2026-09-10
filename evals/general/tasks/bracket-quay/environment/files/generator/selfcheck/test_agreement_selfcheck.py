"""Build-time pre-check: anchor agreement on pristine (red) and fixed (green)."""

from quaydoc.links import target_for
from quaydoc.slugs import anchor_of, fragment_of
from quaydoc.toc import AnchorMap

CASES = [
    "Plain Heading", "Setup & First Steps", "FAQ: v2", "R & D pipeline",
    "A & B / C", "Hello, World!", "Release 2.2: summary", "", "Café Noir",
]


def test_toc_anchor_matches_shared_slug():
    for title in CASES:
        assert AnchorMap().anchor_for(title) == anchor_of(title)


def test_link_target_matches_shared_slug():
    for title in CASES:
        assert target_for(title) == fragment_of(title)
