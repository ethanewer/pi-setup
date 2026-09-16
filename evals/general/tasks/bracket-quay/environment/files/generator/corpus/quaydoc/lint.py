"""Source-level linting (``quaydoc lint``).

The checker validates a *built* site; the linter validates the *sources*
before a build: trailing whitespace, tabs, unresolved reference targets,
heading ids that collide within one page, missing front matter titles, and
links whose relative targets do not exist in the tree.  ``quaydoc lint``
exits nonzero when any error is found, so it can run in CI before the
publish step.
"""

from __future__ import annotations

import os
import re

from quaydoc import finder, slugs
from quaydoc.inline import parse_inline
from quaydoc.links import normalize_title
from quaydoc.nodes import RefLink
from quaydoc.parser import parse_document
from quaydoc.util import read_text

_TRAILING_WS = re.compile(r"[ \t]+$")


class LintFinding:
    """One finding from the source linter."""

    __slots__ = ("severity", "code", "path", "message")

    def __init__(self, severity, code, path, message):
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message

    def render(self):
        return f"{self.severity} [{self.code}] {self.path}: {self.message}"


def lint_tree(root, config):
    """Lint every source file under ``root``; returns the finding list."""
    findings = []
    heading_ids = {}
    for full, rel in finder.iter_candidates(root, config):
        text = read_text(full)
        findings.extend(_lint_file(rel, text))
        doc = parse_document(text, rel)
        for level, title in doc.headings:
            anchor = slugs.anchor_of(title)
            if anchor in heading_ids.get(rel, ()):
                findings.append(LintFinding(
                    "error", "duplicate-anchor", rel,
                    f"anchor {anchor!r} for {title!r} already used on page"))
            heading_ids.setdefault(rel, []).append(anchor)
        if not doc.frontmatter.get("title"):
            findings.append(LintFinding(
                "warning", "no-title", rel,
                "page has no front matter title"))
    return findings


def _lint_file(rel, text):
    findings = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if _TRAILING_WS.search(line):
            findings.append(LintFinding(
                "warning", "trailing-whitespace", f"{rel}:{lineno}",
                "remove trailing whitespace"))
        if "\t" in line:
            findings.append(LintFinding(
                "warning", "tab", f"{rel}:{lineno}",
                "tabs are not allowed in sources"))
    return findings


def link_targets(root, config):
    """Return the set of targetable names: normalized titles and rel paths."""
    titles = set()
    paths = set()
    for full, rel in finder.iter_candidates(root, config):
        paths.add(rel)
        doc = parse_document(read_text(full), rel)
        if doc.frontmatter.get("title"):
            titles.add(normalize_title(str(doc.frontmatter["title"])))
        for level, title in doc.headings:
            titles.add(normalize_title(title))
    return titles, paths


def check_references(root, config):
    """Report ``[[...]]`` references that resolve to nothing."""
    titles, paths = link_targets(root, config)
    findings = []
    files = list(finder.iter_candidates(root, config))
    for full, rel in files:
        doc = parse_document(read_text(full), rel)
        for block in doc.blocks:
            _walk_refs(block, rel, titles, paths, findings)
    return findings


def _walk_refs(node, rel, titles, paths, findings):
    from quaydoc.nodes import Admonition, BlockQuote, Heading, List, ListItem
    if isinstance(node, RefLink):
        target = node.target.strip()
        if "/" not in target and not target.endswith((".qd", ".md")) \
                and normalize_title(target) not in titles:
            findings.append(LintFinding(
                "error", "unresolved-ref", rel,
                f"reference {target!r} matches no page or heading"))
        return
    for attr in ("children", "blocks", "inlines"):
        value = getattr(node, attr, None)
        if value:
            for child in value:
                _walk_refs(child, rel, titles, paths, findings)





from quaydoc import finder, slugs
from quaydoc.parser import parse_document
from quaydoc.util import read_text

_LONG_PARA = 500
_TODO_RE = ("TODO", "FIXME", "XXX")


class QualityFinding:
    """One quality finding for a page."""

    __slots__ = ("code", "path", "message")

    def __init__(self, code, path, message):
        self.code = code
        self.path = path
        self.message = message

    def render(self):
        return f"{self.code} {self.path}: {self.message}"


def quality_check(root, config, long_para=_LONG_PARA):
    """Run the quality checks over a tree; returns a finding list."""
    findings = []
    anchors = {}
    for full, rel in finder.iter_candidates(root, config):
        text = read_text(full)
        doc = parse_document(text, rel)
        findings.extend(_page_findings(rel, doc, long_para))
        for level, title in doc.headings:
            anchor = slugs.anchor_of(title)
            anchors.setdefault(anchor, []).append((rel, title))
    for anchor, owners in sorted(anchors.items()):
        if len(owners) > 1 and len({rel for rel, _ in owners}) > 1:
            where = ", ".join(f"{rel} ({title!r})"
                              for rel, title in owners[:3])
            findings.append(QualityFinding(
                "site-duplicate-anchor",
                "site",
                f"anchor {anchor!r} used by several pages: {where}, "
                "cross-page references to it may be ambiguous"))
    return findings


def _page_findings(rel, doc, long_para):
    findings = []
    prev_level = 0
    heading_count = 0
    for level, title in doc.headings:
        heading_count += 1
        if prev_level and level > prev_level + 1:
            findings.append(QualityFinding(
                "heading-jump", rel,
                f"heading level jumps from h{prev_level} to h{level} "
                f"({title!r})"))
        prev_level = level
    if not heading_count:
        findings.append(QualityFinding(
            "no-headings", rel, "page has no headings"))
    plain = _plaintext(doc)
    for line in _long_lines(doc, long_para):
        findings.append(QualityFinding(
            "long-paragraph", rel, f"{line[0]}: paragraph is {line[1]} chars"))
    for marker in _TODO_RE:
        if marker in plain:
            findings.append(QualityFinding(
                "todo", rel, f"contains {marker} marker"))
    for block in doc.blocks:
        from quaydoc.nodes import Admonition
        if isinstance(block, Admonition) and not block.children:
            findings.append(QualityFinding(
                "empty-admonition", rel,
                f"empty {block.kind} admonition"))
    return findings


def _plaintext(doc):
    from quaydoc import markup
    return markup.plaintext_blocks(doc.blocks)


def _long_lines(doc, limit):
    out = []
    from quaydoc.nodes import Paragraph
    for lineno, block in enumerate(doc.blocks, 1):
        if isinstance(block, Paragraph):
            text = "".join(getattr(i, "text", "") for i in block.inlines)
            if len(text) > limit:
                out.append((lineno, len(text)))
    return out
