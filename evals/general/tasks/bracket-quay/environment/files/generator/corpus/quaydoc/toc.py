"""Table of contents and heading anchors.

A rendered page assigns every heading an ``id`` attribute; the table of
contents sidebar and the ``[[...]]`` references elsewhere point at those ids.

IMPORTANT INVARIANT: :meth:`AnchorMap.anchor_for` and
:func:`quaydoc.links.target_for` (which wraps :func:`quaydoc.slugs.anchor_of`)
must produce identical fragments for the same title — the id side of the
pipeline and the link side of the pipeline have to stay in lock-step or every
fragment link on the page breaks.
"""

from __future__ import annotations

import re

from quaydoc import slugs
from quaydoc.util import escape_html


class Section:
    """One heading in the section tree."""

    def __init__(self, level, title):
        self.level = level
        self.title = title
        self.anchor = None      # assigned by AnchorMap.assign
        self.children = []

    def __repr__(self):
        return f"<Section h{self.level} {self.title!r} -> {self.anchor!r}>"


def build_sections(headings):
    """Fold a flat ``[(level, title), ...]`` list into a section forest."""
    roots = []
    stack = []
    for level, title in headings:
        node = Section(level, title)
        while stack and stack[-1].level >= level:
            stack.pop()
        if stack:
            stack[-1].children.append(node)
        else:
            roots.append(node)
        stack.append(node)
    return roots


class AnchorMap:
    """Assigns unique ``id`` attributes to the headings of one page.

    Uniqueness is a render-time concern: duplicates inside one page get
    ``-2``, ``-3`` suffixes.  The base spelling of every id comes from
    :meth:`anchor_for`.
    """

    def __init__(self):
        self._used = set()
        self.by_title = {}

    def anchor_for(self, title):
        """Compute the base anchor id for a heading title."""
        text = str(title)
        text = text.replace("&", "and")
        text = text.replace(":", "")
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        slug = re.sub(r"-{2,}", "-", slug)
        return slug or "section"

    def lookup(self, title):
        """Return the assigned id for a title, or ``None``."""
        return self.by_title.get(title)

    def take(self, title):
        """Assign and remember a unique id for ``title``."""
        base = self.anchor_for(title)
        candidate, n = base, 2
        while candidate in self._used:
            candidate = f"{base}-{n}"
            n += 1
        self._used.add(candidate)
        self.by_title[title] = candidate
        return candidate

    def assign(self, sections):
        """Assign anchors to every section in the forest; return flat list."""
        out = []
        for section in sections:
            section.anchor = self.take(section.title)
            out.append(section)
            out.extend(self.assign(section.children))
        return out


def toc_html(sections, current_anchor=None, wrap=True):
    """Render the section forest as a nested ``<ul>`` of jump links."""
    if not sections:
        return ""
    parts = ['<ul class="toc">']
    for section in sections:
        parts.append("<li>")
        cls = ' class="current"' if section.anchor == current_anchor else ""
        href = f"#{section.anchor}" if section.anchor else "#"
        parts.append(f'<a href="{href}"{cls}>{escape_html(section.title)}</a>')
        if section.children:
            parts.append(toc_html(section.children, current_anchor, wrap=False))
        parts.append("</li>")
    parts.append("</ul>")
    inner = "".join(parts)
    return inner



class NumberedSection:
    """One section with its computed number and display title."""

    __slots__ = ("level", "number", "title", "anchor", "children")

    def __init__(self, level, number, title, anchor):
        self.level = level
        self.number = number
        self.title = title
        self.anchor = anchor
        self.children = []

    @property
    def display_title(self):
        return f"{self.number} {self.title}"

    def __repr__(self):
        return f"<NumberedSection {self.number} {self.title!r}>"


def number_sections(sections, counters=None, prefix="", depth=0):
    """Walk a section forest and return a mirrored, numbered tree.

    ``counters`` is a list of per-level counters carried through recursion —
    it is exposed so callers can reset or inspect numbering.
    """
    if counters is None:
        counters = []
    while len(counters) <= depth:
        counters.append(0)
    out = []
    for section in sections:
        counters[depth] += 1
        number = prefix + str(counters[depth])
        node = NumberedSection(section.level, number, section.title,
                               section.anchor)
        node.children = number_sections(section.children, counters,
                                        prefix=f"{number}.", depth=depth + 1)
        out.append(node)
    return out


def number_lines(titles_with_anchors):
    """Map ``(level, title)`` pairs to ``(level, numbered_title, anchor)``.

    Convenience used by renderers that want per-heading numbers without
    building the full section forest.
    """
    counters = []

    def bump(level):
        while len(counters) < level:
            counters.append(0)
        # a deeper heading with no shallower one yet counts as section 1
        promoted = (level > 1 and
                    all(c == 0 for c in counters[:level - 1]))
        if promoted:
            for i in range(level - 1):
                counters[i] = 1
        counters[level - 1] += 1
        for deeper in range(level, len(counters)):
            counters[deeper] = 0
        if promoted:
            return str(counters[level - 1])
        return ".".join(str(c) for c in counters[:level])

    out = []
    for level, title, anchor in titles_with_anchors:
        out.append((level, f"{bump(level)} {title}", anchor))
    return out
