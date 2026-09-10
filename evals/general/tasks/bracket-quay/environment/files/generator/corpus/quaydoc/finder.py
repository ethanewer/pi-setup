"""Source discovery and ignore rules.

A documentation root is walked recursively; files with a documentation
extension are candidates.  Anything inside the configured output directory,
inside hidden directories, or matched by ``.quayignore`` is skipped.
"""

from __future__ import annotations

import fnmatch
import os
from pathlib import Path

from quaydoc.urls import is_doc_path

IGNORE_NAME = ".quayignore"


def load_ignore_patterns(root):
    """Return the list of glob patterns from ``root``/.quayignore."""
    ignore_path = os.path.join(root, IGNORE_NAME)
    patterns = []
    if os.path.exists(ignore_path):
        with open(ignore_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    patterns.append(line)
    return patterns


def matches_ignore(rel_path, patterns):
    """True when a relative posix path matches any ignore pattern."""
    for pattern in patterns:
        if fnmatch.fnmatch(rel_path, pattern) or \
                fnmatch.fnmatch(rel_path.split("/")[-1], pattern):
            return True
        if pattern.rstrip("/") in rel_path:
            return True
    return False


def iter_candidates(root, config):
    """Yield (source_path, rel_posix) for every documentation file."""
    root = Path(root)
    out_abs = os.path.abspath(config.output_path)
    patterns = load_ignore_patterns(str(root))
    for dirpath, dirnames, filenames in os.walk(str(root)):
        dirnames[:] = [d for d in dirnames
                       if not (d.startswith(".") or
                               os.path.abspath(os.path.join(dirpath, d))
                               == out_abs)]
        for fname in sorted(filenames):
            full = os.path.join(dirpath, fname)
            rel = os.path.relpath(full, str(root)).replace(os.sep, "/")
            if not is_doc_path(rel):
                continue
            if matches_ignore(rel, patterns):
                continue
            if fname == IGNORE_NAME:
                continue
            yield full, rel


def find_docs(root, config):
    """Sorted list of candidate source files (full paths)."""
    return [full for full, _ in iter_candidates(root, config)]
