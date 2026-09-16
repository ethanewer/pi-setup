"""Build-time pre-check mirror of the hidden fragment-integrity case.

Real invariant test: every ``href="#..."`` (same-page or cross-page) must
resolve to an id on the target page.  FAILS on the pristine (regressed)
tree for headings containing ``&`` or ``:``; passes after the repair.
"""

import os
import re


def build(tmp_path):
    from quaydoc.config import load_config
    from quaydoc.site import Site
    root = tmp_path / "docs"
    root.mkdir()
    titles = ["Setup & First Steps", "FAQ: v2", "R & D pipeline"]
    links = "\n".join(f"- [[{t}]]" for t in titles)
    (root / "index.qd").write_text(
        "---\ntitle: Home\n---\n\n" + links + "\n", encoding="utf-8")
    (root / "guide.qd").write_text(
        "---\ntitle: Guide\n---\n\n" +
        "\n".join(f"## {t}" for t in titles) + "\n", encoding="utf-8")
    site = Site(str(root), load_config(str(root))).load()
    outdir = str(tmp_path / "out")
    site.build(outdir=outdir)
    return outdir


def test_every_fragment_has_an_id(tmp_path):
    outdir = build(tmp_path)
    ids, refs = {}, []
    for dirpath, dirnames, filenames in os.walk(outdir):
        dirnames[:] = [d for d in dirnames if d != "assets"]
        for fname in filenames:
            if fname.endswith(".html"):
                rel = os.path.relpath(os.path.join(dirpath, fname), outdir)
                url = "/" + rel.replace("index.html", "").replace(".html", "/")
                html = open(os.path.join(dirpath, fname),
                            encoding="utf-8").read()
                ids[url] = set(re.findall(r'id="([^"]+)"', html))
                for href in re.findall(r'href="([^"]*#([^"]+))"', html):
                    full, frag = href
                    if full.startswith("#"):
                        refs.append((url, frag))
                    elif full.startswith("/"):
                        refs.append((full.partition("#")[0], frag))
    assert ids, "no ids found (fixture broken)"
    assert refs, "no references found (fixture broken)"
    missing = [f"{page} -> #{frag}" for page, frag in refs
               if frag not in ids.get(page, set())]
    assert not missing, "unresolved fragments: " + "; ".join(missing)
