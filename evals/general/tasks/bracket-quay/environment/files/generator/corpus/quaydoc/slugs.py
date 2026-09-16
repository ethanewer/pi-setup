"""Canonical slugs and anchors.

An anchor is the ``id`` attribute of a rendered heading.  Every part of
quaydoc that needs to name a heading (the table of contents assigns the id,
the link resolver builds ``#fragment`` targets) must agree on the exact same
string, so the single implementation lives here.

Rules (fixed since 0.5.0):

* lowercase,
* any run of characters outside ``[a-z0-9]`` becomes a single ``-``,
* leading/trailing dashes are stripped,
* repeated dashes collapse,
* an empty result falls back to ``"section"``.

The rules are deliberately lossy and intentionally stable: ids never change
between releases unless every consumer changes together.
"""

from __future__ import annotations

import re

_NON_ALNUM_RE = re.compile(r"[^a-z0-9]+")
_DASH_RE = re.compile(r"-{2,}")


def anchor_of(title):
    """Return the canonical anchor id for ``title``.

    >>> anchor_of("Hello, World!")
    'hello-world'
    >>> anchor_of("A & B / C")
    'a-b-c'
    >>> anchor_of("???")
    'section'
    """
    slug = _NON_ALNUM_RE.sub("-", str(title).lower()).strip("-")
    slug = _DASH_RE.sub("-", slug)
    return slug or "section"


def fragment_of(title):
    """Return the ``#`` prefixed fragment for ``title`` (link side)."""
    return "#" + anchor_of(title)


def file_slug(title, fallback="page"):
    """A filesystem-safe slug (no ``/`` ever) used for generated filenames."""
    slug = anchor_of(title)
    slug = slug.replace("/", "-")
    return slug or fallback
