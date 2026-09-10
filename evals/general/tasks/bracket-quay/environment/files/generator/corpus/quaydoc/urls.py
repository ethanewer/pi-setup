"""URL and output-path derivation.

All internal URLs are root-relative (``/guide/install/`` with pretty URLs,
``/guide/install.html`` without).  Root-relative URLs work identically under
the dev server, a static host, and a ``file://`` mount, and keep the builder
free of fragile relative-depth arithmetic.
"""

from __future__ import annotations

import os
import posixpath

DOC_EXTS = (".qd", ".md", ".markdown", ".mdown")


def strip_ext(rel_posix):
    """Drop a documentation extension from a posix relative path."""
    for ext in DOC_EXTS:
        if rel_posix.endswith(ext):
            return rel_posix[: -len(ext)]
    return rel_posix


def page_posix(rel_path):
    """Posix-style relative path without the source extension."""
    return strip_ext(os.path.relpath(rel_path).replace(os.sep, "/"))


_HOME = ("index", "README")


def page_url(rel_posix, pretty):
    """Root-relative URL for a page given its extension-less posix path."""
    if rel_posix in _HOME:
        return "/"
    if pretty:
        return "/" + rel_posix + "/"
    return "/" + rel_posix + ".html"


def output_rel(rel_posix, pretty):
    """Output-relative path (from the site root) for a page."""
    if rel_posix in _HOME:
        return "index.html"
    if pretty:
        return posixpath.join(rel_posix, "index.html")
    return rel_posix + ".html"


def output_path(outdir, rel_posix, pretty):
    """Absolute output path for a page."""
    return os.path.normpath(
        os.path.join(outdir, output_rel(rel_posix, pretty)))


def is_doc_path(rel_posix):
    return rel_posix.endswith(DOC_EXTS)


def canonical_url(url, base_url=""):
    """The absolute canonical form of a root-relative URL."""
    if url in ("", "/"):
        base = (base_url or "").rstrip("/")
        return (base + "/") if base else "/"
    if url.startswith(("http://", "https://")):
        return url
    base = (base_url or "").rstrip("/")
    return base + url if base else url


def is_canonical(url, base_url=""):
    """True when ``url`` is already in canonical form."""
    return url == canonical_url(url, base_url)


def normalize_url(url):
    """Collapse duplicate slashes and a trailing index.html to index."""
    while "//" in url:
        url = url.replace("//", "/")
    return url



import json
import os
import re

from quaydoc.util import write_text

_VERSION_RE = re.compile(r"^v([0-9]+(?:\.[0-9]+)*|latest)$")


def discover_versions(root):
    """Return the versions present as ``v*`` subdirectories of ``root``."""
    versions = []
    if not os.path.isdir(root):
        return versions
    for entry in sorted(os.listdir(root)):
        if _VERSION_RE.match(entry) and os.path.isdir(
                os.path.join(root, entry)):
            versions.append(entry)
    return versions


def version_label(version_dir):
    """Human label for a version directory name."""
    if version_dir == "vlatest":
        return "latest"
    return version_dir[1:]


def version_url(version_dir, pretty, rel_posix):
    """URL of a page inside a version tree."""
    from quaydoc.urls import page_url
    if version_dir == "vlatest":
        return page_url(rel_posix, pretty)
    return page_url("v" + version_dir[1:] + "/" + rel_posix, pretty)


def all_build_roots(root, config):
    """Yield ``(version_dir_or_None, source_root, path_prefix)`` triples."""
    roots = []
    versions = discover_versions(root)
    if not versions:
        roots.append((None, root, ""))
        return roots
    for version in versions:
        prefix = "" if version == "vlatest" else "/" + version
        roots.append((version, os.path.join(root, version), prefix))
    return roots


def write_versions_manifest(pages_by_version, outdir):
    """Write ``versions.json`` describing built versions + page counts."""
    payload = []
    for version, pages in pages_by_version:
        payload.append({
            "version": version_label(version) if version else "current",
            "directory": version or "",
            "pages": [page.url for page in pages],
        })
    write_text(os.path.join(outdir, "versions.json"),
               json.dumps(payload, indent=1))
    return payload
