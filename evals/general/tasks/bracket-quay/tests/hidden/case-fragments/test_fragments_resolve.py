"""Hidden case: rendered-page fragment integrity for symbol-heavy headings.

Every rendered page must be internally consistent: each ``href="#..."``
fragment must match the ``id`` of an element on the target page.  Headings
whose titles contain an ampersand or a colon are the adversarial cases here
— the shipped suite deliberately never checks them.
"""

import re

from quaydoc.parser import parse_document
from quaydoc.util import read_text

TRIGGER_TITLES = [
    "Setup & First Steps",
    "FAQ: v2",
    "R & D pipeline",
    "Notes on C++ & Java",
    "Release 2.2: summary",
]

PAGES = {"index.qd": "", "guide.qd": ""}

INDEX = """---
title: Home
order: 10
---

{links}
"""

GUIDE_HEAD = """---
title: Guide
order: 20
---

"""

GUIDE_SECTION = "## {title}\n\nBody of the {title} section."


def write_docs(tmp_path):
    root = tmp_path / "docs"
    root.mkdir()
    links = "\n".join(f"- [[{t}]]" for t in TRIGGER_TITLES)
    guide_body = "\n\n".join(
        GUIDE_SECTION.format(title=t) for t in TRIGGER_TITLES)
    (root / "index.qd").write_text(INDEX.format(links=links),
                                   encoding="utf-8")
    (root / "guide.qd").write_text(
        GUIDE_HEAD + guide_body + "\n", encoding="utf-8")
    return root


def build(tmp_path):
    from quaydoc.config import load_config
    from quaydoc.site import Site
    root = write_docs(tmp_path)
    site = Site(str(root), load_config(str(root))).load()
    outdir = str(tmp_path / "out")
    site.build(outdir=outdir)
    return site, outdir


def collect_fragments(outdir):
    """Page id sets keyed by URL, and (page_url, fragment) reference pairs.

    References are root-relative-ish ("/guide/#setup-first-steps" and bare
    "#frag" same-page links); a fragment must resolve on the target page.
    """
    ids, refs = {}, []
    for rel, html in _walk_html(outdir):
        url = "/" + rel.replace("index.html", "").replace(".html", "/")
        if rel == "guide/index.html":
            url = "/guide/"
        ids[url] = set(re.findall(r'id="([^"]+)"', html))
        for href in re.findall(r'href="([^"]*#([^"]+))"', html):
            full, frag = href
            if full.startswith("#"):
                refs.append((url, frag))
            elif full.startswith("/"):
                target, _, _ = full.partition("#")
                refs.append((target, frag))
    return ids, refs


def _walk_html(outdir):
    import os
    for dirpath, dirnames, filenames in os.walk(outdir):
        dirnames[:] = [d for d in dirnames if d != "assets"]
        for fname in sorted(filenames):
            if fname.endswith(".html"):
                full = os.path.join(dirpath, fname)
                rel = os.path.relpath(full, outdir)
                with open(full, encoding="utf-8") as fh:
                    yield rel, fh.read()


def test_every_fragment_resolves(tmp_path):
    _site, outdir = build(tmp_path)
    ids, refs = collect_fragments(outdir)
    problems = []
    for page_url, frag in refs:
        if frag not in ids.get(page_url, set()):
            problems.append(f"{page_url} -> #{frag} has no matching id")
    assert not problems, "unresolved fragments: " + "; ".join(problems)


def test_trigger_heading_ids_are_canonical(tmp_path):
    _site, outdir = build(tmp_path)
    import os
    guide_path = os.path.join(outdir, "guide", "index.html")
    guide_html = open(guide_path, encoding="utf-8").read()
    for title in TRIGGER_TITLES:
        from quaydoc.slugs import anchor_of
        expected = anchor_of(title)
        assert f'id="{expected}"' in guide_html, \
            f"heading {title!r} must carry id {expected!r}"
