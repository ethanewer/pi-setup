"""Hidden case: the CLI build+check loop stays clean on symbol-heavy docs.

Building a docset whose headings contain ampersands and colons, then
running ``quaydoc check`` over the output, must report zero issues — the
checker validates the published artefact, so any drift between the ids the
toc assigns and the fragments the links compute shows up here as
``broken-fragment``.
"""

import os
import subprocess
import sys
from pathlib import Path

TRIGGERS = [
    "Setup & First Steps",
    "FAQ: v2",
    "Ampersand & Friends",
    "Guide: part two",
]

DOCS = {
    "index.qd": "---\ntitle: Home\norder: 1\n---\n\n{links}\n",
    "guide.qd": "---\ntitle: Guide\norder: 2\n---\n\n{titles}\n",
}


def write_tree(root, files):
    for rel, body in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")


def build_and_check(tmp_path):
    root = tmp_path / "docs"
    root.mkdir()
    links = "\n".join(f"- [[{t}]]" for t in TRIGGERS)
    titles = "\n".join(f"## {t}" for t in TRIGGERS)
    write_tree(root, {
        "index.qd": DOCS["index.qd"].format(links=links),
        "guide.qd": DOCS["guide.qd"].format(titles=titles),
    })
    outdir = str(tmp_path / "site")
    build = subprocess.run(
        [sys.executable, "-m", "quaydoc.cli", "build", str(root),
         "-o", outdir],
        capture_output=True, text=True)
    assert build.returncode == 0, build.stderr
    check = subprocess.run(
        [sys.executable, "-m", "quaydoc.cli", "check", outdir],
        capture_output=True, text=True)
    return check, outdir, root


def test_cli_check_reports_no_issues(tmp_path):
    check, outdir, _root = build_and_check(tmp_path)
    assert check.returncode == 0, check.stdout + check.stderr
    assert "0 error(s), 0 warning(s)" in check.stdout


def test_built_html_links_match_ids(tmp_path):
    _check, outdir, _root = build_and_check(tmp_path)
    from quaydoc.slugs import anchor_of
    guide_html = (Path(outdir) / "guide" / "index.html").read_text(
        encoding="utf-8")
    index_html = (Path(outdir) / "index.html").read_text(encoding="utf-8")
    for title in TRIGGERS:
        fragment = anchor_of(title)
        assert f'id="{fragment}"' in guide_html, \
            f"heading {title!r} must carry canonical id {fragment!r}"
        assert f'href="/guide/#{fragment}"' in index_html, \
            f"link to {title!r} must point at canonical fragment {fragment!r}"
