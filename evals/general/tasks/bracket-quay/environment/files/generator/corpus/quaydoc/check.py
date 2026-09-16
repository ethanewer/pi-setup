"""Link-integrity checker for a built site.

``quaydoc check`` walks the HTML pages of a build directory and reports
errors in the published artefact itself:

* ``broken-fragment``   an internal ``#frag`` link whose target page has no
                        element with that id,
* ``missing-page``      an internal link to a page that was not built,
* ``missing-image``     an ``<img src>`` that does not exist next to the site,
* ``duplicate-id``      the same id attribute used twice on one page.

The checker parses the rendered HTML files directly — it validates the
output, not the source — so any mismatch between the two sides of the
anchor pipeline shows up here as ``broken-fragment``.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit

from quaydoc.errors import CheckError
from quaydoc.util import ensure_dir, write_text

EXTERNAL = ("http://", "https://", "mailto:", "ftp://", "data:", "//",
            "javascript:")


def _is_external(url):
    return url.startswith(EXTERNAL)


@dataclass
class Issue:
    """One problem found in a built site."""

    severity: str          # "error" | "warning"
    code: str
    message: str
    path: str = ""

    def render(self):
        return f"{self.severity} [{self.code}] {self.path}: {self.message}"


class _ScanParser(HTMLParser):
    """Collects ids, fragment hrefs, page hrefs and image sources."""

    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.ids = set()
        self._id_counts = {}
        self.fragments = []
        self.hrefs = []
        self.images = []

    def handle_starttag(self, tag, attrs):
        attr_map = dict(attrs)
        ident = attr_map.get("id")
        if ident:
            self.ids.add(ident)
            self._id_counts[ident] = self._id_counts.get(ident, 0) + 1
        href = attr_map.get("href")
        if href is not None:
            if href.startswith("#"):
                self.fragments.append(href[1:])
            else:
                self.hrefs.append(href)
        src = attr_map.get("src")
        if src is not None:
            self.images.append(src)


def _scan_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        html = fh.read()
    parser = _ScanParser()
    try:
        parser.feed(html)
    except Exception:
        pass
    return parser


def _url_to_file(url, build_dir):
    """Map a root-relative URL to a candidate file path."""
    parts = urlsplit(unquote(url))
    path = parts.path
    if path.startswith("/"):
        path = path[1:]
    if not path:
        path = "index.html"
    candidate = os.path.join(build_dir, path)
    if os.path.isdir(candidate):
        candidate = os.path.join(candidate, "index.html")
    elif not os.path.exists(candidate) and not path.endswith(".html"):
        if os.path.isfile(candidate + ".html"):
            candidate = candidate + ".html"
    return candidate


class Checker:
    """Runs the integrity checks over one build directory."""

    def __init__(self, build_dir):
        self.build_dir = os.path.abspath(build_dir)
        if not os.path.isdir(self.build_dir):
            raise CheckError(f"{self.build_dir}: not a directory")

    def check(self):
        """Return the list of :class:`Issue` objects (may be empty)."""
        parsed = [(rel, _scan_file(path))
                  for rel, path in self._html_files()]
        ids_by_rel = {rel: scan.ids for rel, scan in parsed}
        issues = []

        for rel, scan in parsed:
            if not scan.fragments and not scan.hrefs and not scan.ids \
                    and not scan.images:
                issues.append(Issue(
                    "warning", "empty-page",
                    "page contains no headings, links or ids", rel))
            for ident in sorted(scan.ids):
                if scan._id_counts.get(ident, 0) > 1:
                    issues.append(Issue(
                        "error", "duplicate-id",
                        f"id {ident!r} used more than once on the page", rel))
                    break
            for frag in scan.fragments:
                if frag not in scan.ids:
                    issues.append(Issue(
                        "error", "broken-fragment",
                        f"fragment #{frag} has no matching id on this page",
                        rel))
            for href in scan.hrefs:
                if _is_external(href):
                    continue
                if href.startswith("#"):
                    continue
                target = _url_to_file(href, self.build_dir)
                if not os.path.isfile(target):
                    issues.append(Issue(
                        "error", "missing-page",
                        f"link target {href!r} was not built", rel))
                    continue
                frag = urlsplit(href).fragment
                if frag:
                    rel_target = os.path.relpath(target, self.build_dir)
                    target_ids = ids_by_rel.get(rel_target, set())
                    if frag not in target_ids:
                        issues.append(Issue(
                            "error", "broken-fragment",
                            f"fragment #{frag} not found on target {href!r}",
                            rel))
            for src in scan.images:
                if _is_external(src):
                    continue
                target = _url_to_file(src, self.build_dir)
                if not os.path.isfile(target):
                    issues.append(Issue(
                        "error", "missing-image",
                        f"image {src!r} not found", rel))

        issues.sort(key=lambda i: (i.path, i.code, i.message))
        return issues

    def _html_files(self):
        out = []
        for dirpath, dirnames, filenames in os.walk(self.build_dir):
            dirnames[:] = [d for d in dirnames if d != "assets"]
            for fname in sorted(filenames):
                if fname.endswith(".html"):
                    full = os.path.join(dirpath, fname)
                    out.append((os.path.relpath(full, self.build_dir), full))
        out.sort()
        return out

    def encoding_issues(self):
        """Report HTML files that are not clean UTF-8."""
        issues = []
        for rel, path in self._html_files():
            try:
                with open(path, "rb") as fh:
                    fh.read().decode("utf-8")
            except UnicodeDecodeError as exc:
                issues.append(Issue(
                    "error", "bad-encoding",
                    f"not valid UTF-8 ({exc})", rel))
        return issues

    def feed_checks(self):
        """Cross-check sitemap.xml / feed.xml against what was built.

        Both files must parse as XML and every URL they advertise must have
        a corresponding file in the output directory.
        """
        import xml.etree.ElementTree as ET
        issues = []
        for name, tag, url_attr in (
                ("sitemap.xml", "url", "loc"),
                ("feed.xml", "entry", "link")):
            path = os.path.join(self.build_dir, name)
            if not os.path.isfile(path):
                continue
            try:
                tree = ET.parse(path)
            except ET.ParseError as exc:
                issues.append(Issue(
                    "warning", "bad-xml", f"{name} is not well-formed "
                    f"XML ({exc})", name))
                continue
            for elem in tree.iter(tag):
                loc = elem.findtext(url_attr) or elem.get("href")
                if not loc:
                    continue
                url = loc.split("#", 1)[0]
                if url.startswith("http") or url.startswith("//"):
                    continue
                target = _url_to_file(url, self.build_dir)
                if not os.path.isfile(target):
                    issues.append(Issue(
                        "warning", "feed-target-missing",
                        f"{name} advertises {loc!r} which was not built",
                        name))
        return issues

    def all_issues(self):
        """Every check in one list (HTML, encoding, feeds)."""
        return self.check() + self.encoding_issues() + self.feed_checks()

    @staticmethod
    def list_codes():
        """Every issue code the checker can emit, with one-line meanings."""
        return {
            "broken-fragment": "a #fragment link with no matching id",
            "missing-page": "an internal link whose page was not built",
            "missing-image": "an image source that does not exist",
            "duplicate-id": "an id used more than once on one page",
            "empty-page": "a page with no headings, links or ids",
            "bad-encoding": "an HTML file that is not valid UTF-8",
            "feed-target-missing": "sitemap/feed advertises an unbuilt URL",
            "bad-xml": "sitemap.xml or feed.xml is not well-formed XML",
        }

    @staticmethod
    def write_report(issues, path):
        """Write a human-readable report; returns the error count."""
        ensure_dir(os.path.dirname(os.path.abspath(path)))
        errors = [i for i in issues if i.severity == "error"]
        lines = ["No issues."] if not issues else [i.render() for i in issues]
        lines.append("")
        lines.append(f"{len(errors)} error(s), "
                     f"{len(issues) - len(errors)} warning(s)")
        write_text(path, "\n".join(lines))
        return len(errors)
