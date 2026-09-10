"""Hidden case: the anchor inventory written for a symbol-heavy docset.

The build emits headings.json; every heading's recorded anchor must match
the canonical fragment spelling, otherwise TOC jump-links and references
could drift even when the pages happen to render.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

from quaydoc.slugs import anchor_of

TITLES = ["Setup & First Steps", "FAQ: v2", "R & D pipeline"]


def test_headings_json_matches_canonical_anchors(tmp_path):
    root = tmp_path / "docs"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\ntitle: Home\n---\n\n" +
        "\n".join(f"## {t}" for t in TITLES) + "\n",
        encoding="utf-8")
    outdir = str(tmp_path / "site")
    build = subprocess.run(
        [sys.executable, "-m", "quaydoc.cli", "build", str(root),
         "-o", outdir],
        capture_output=True, text=True)
    assert build.returncode == 0, build.stderr
    manifest = json.loads(open(os.path.join(outdir, "headings.json"),
                               encoding="utf-8").read())
    anchors = {e["title"]: e["anchor"] for e in manifest}
    for title in TITLES:
        assert anchors.get(title) == anchor_of(title), \
            f"{title!r} recorded as {anchors.get(title)!r}"
