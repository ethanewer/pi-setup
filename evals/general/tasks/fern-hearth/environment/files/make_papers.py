#!/usr/bin/env python3
"""Generate the bundled paper index fixtures (detail pages) under /app/papers.
Clean-room knowledge; all names/orgs are invented."""

import os

OUT = "/app/papers"
os.makedirs(OUT, exist_ok=True)

# id -> (title, affiliation_org, official_repo_slug, has_detail_page)
# affiliation_org == ""  => page exists but has no affiliation  (unresolvable)
# has_detail_page False  => listed in the index but no detail page (draft)
PAPERS = [
    ("fh-1",  "Low-Latency Sidelobe Cancellation for Phased Feeds", "Arcadium", "sidelobe", True),
    ("fh-207", "Canary Grid Scheduling over Ambient Meshes",        "Oakmere",  "canarygrid", True),
    ("fh-312", "Traversal Hints for Sparse Hierarchical Bins",      "Vellun",   "traversalhints", True),
    ("fh-450", "Adaptive Hearth Nomenclature Charts",               "Oakmere",  "hearthcool", True),
    ("fh-183", "Quantum Smoke Trace Reconstruction",                "Arcadium", "qsmoke", True),
    ("fh-560", "Broadcast Memo Transport for Editions Relays",      "",         "memo", True),
    ("fh-601", "Skylark: a Chord Indexer (draft, unpublished)",     "Arcadium", "chordidx", False),
]

OTHER_ORGS = ["ForgeAway", "Cinderlane", "Halcyon"]


def html_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def ordn(pid):
    return sum(ord(c) for c in pid) % len(OTHER_ORGS)


index_rows = []
for (pid, title, aff, slug, has_detail) in PAPERS:
    index_rows.append(
        '<tr data-pid="%s"><td class="pid">%s</td>'
        '<td class="title"><a class="detail" href="%s.html">%s</a></td></tr>\n'
        % (pid, pid, pid, html_escape(title)))
    if not has_detail:
        continue
    aff_div = ('<div class="affiliation">%s</div>\n' % html_escape(aff)) if aff else ""
    cands = [
        '<li><a class="repo" href="https://github.com/%s/%s">paper code</a></li>\n' % (aff, slug),
        '<li><a class="repo" href="https://github.com/%s/%s-rework">community rework</a></li>\n'
        % (OTHER_ORGS[ordn(pid)], slug),
        '<li><a class="repo" href="https://gitlab.com/%s/%s">internal mirror</a></li>\n' % (aff, slug),
    ]
    detail = (
        '<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>%s</title></head>\n'
        '<body>\n<article id="%s">\n'
        '<h1>%s</h1>\n%s'
        '<ul class="repos">\n%s</ul>\n'
        '<p class="note">The author-maintained repository is the GitHub repository '
        'whose owner matches this paper\'s affiliation.</p>\n'
        '</article>\n</body></html>\n'
        % (html_escape(title), pid, html_escape(title), aff_div, "".join(cands)))
    with open(os.path.join(OUT, pid + ".html"), "w") as f:
        f.write(detail)

index = ('<!DOCTYPE html>\n<html><head><meta charset="utf-8">'
         '<title>Fast Serve paper index</title></head>\n<body>\n'
         '<h1>Index</h1>\n'
         '<p>Each entry links to a detail page.</p>\n'
         '<table id="papers">\n' + "".join(index_rows) +
         '</table>\n</body></html>\n')
with open(os.path.join(OUT, "index.html"), "w") as f:
    f.write(index)

with open(os.path.join(OUT, "README.md"), "w") as f:
    f.write("# Fred Hearth catalogue fixture\n\nStatic index + per-paper pages.\n")

print("generated %s with %d papers" % (OUT, len(PAPERS)))