"""Migration helpers for configs and front matter from older quaydoc.

Version 0.8 configs used ``[build] output = "..."`` and front matter spelled
``issued:`` / ``author:``; 0.9 normalised those to ``output_dir`` and
``date`` / ``authors``.  The migration walks a tree and rewrites both in
place, preserving everything else.
"""

from __future__ import annotations

import os
import re

from quaydoc import finder
from quaydoc.util import write_text

_KEY_MAP = {
    "issued": "date",
    "author": "authors",
    "output": "output_dir",
}
_FRONTMATTER_KEY = re.compile(r"^([A-Za-z0-9_-]+):(.*)$")
_TOML_LINE = re.compile(r"^(\s*)([A-Za-z0-9_-]+)\s*=\s*(.*)$")


def migrate_tree(root, config, dry_run=False):
    """Rewrite config + front matter keys in ``root``.

    Returns a list of ``(display_path, [(line, summary)])`` records; with
    ``dry_run`` nothing is written.
    """
    records = []
    config_path = os.path.join(config.root, "quaydoc.toml")
    if os.path.isfile(config_path):
        diffs = _migrate_toml_file(config_path)
        if diffs:
            records.append(("quaydoc.toml", diffs))
    for full, rel in finder.iter_candidates(root, config):
        diffs = _migrate_frontmatter_file(full)
        if diffs:
            records.append((rel, diffs))
    if not dry_run:
        for display, diffs in records:
            _apply(display, diffs, config.root)
    return records


def _migrate_toml_file(path):
    diffs = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    for lineno, line in enumerate(lines, 1):
        m = _TOML_LINE.match(line)
        if m and m.group(2) in _KEY_MAP:
            diffs.append((lineno, f"{m.group(2)} -> {_KEY_MAP[m.group(2)]}"))
    return diffs


def _migrate_frontmatter_file(path):
    diffs = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    if not lines or not lines[0].strip() == "---":
        return diffs
    for lineno, line in enumerate(lines, 1):
        if lineno == 1:
            continue
        if line.strip() == "---":
            break
        m = _FRONTMATTER_KEY.match(line.strip())
        if m and m.group(1) in _KEY_MAP:
            diffs.append((lineno, f"{m.group(1)} -> {_KEY_MAP[m.group(1)]}"))
    return diffs


def _apply(display, diffs, root):
    """Apply per-line key renames in place."""
    path = display
    if display == "quaydoc.toml":
        path = os.path.join(root, display)
    else:
        path = os.path.join(root, display)
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines(keepends=True)
    for lineno, _summary in sorted(diffs):
        line = lines[lineno - 1]
        for old, new in _KEY_MAP.items():
            line = line.replace(old, new, 1)
            break  # only the first rename applies per line
        lines[lineno - 1] = line
    write_text(path, "".join(lines))
