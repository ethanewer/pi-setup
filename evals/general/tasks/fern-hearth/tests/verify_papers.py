#!/usr/bin/env python3
"""Paper->official-repository verifier for fern-hearth.

Independently derives the expected mapping by parsing the bundled fixture
(/app/papers/index.html and each detail page) and cross-referencing the paper's
affiliation against candidate repository URLs. Then checks /app/paper_links.json
(JSON-lines) and /app/urls.tsv against it. Requires no knowledge of the oracle's
implementation. Must run on the fresh instance to catch a broken/missing mapping.
"""
import json
import os
import sys
from urllib.parse import urlsplit

sys.path.insert(0, "/tests/helpers")
import canonical  # noqa: E402

PAPERS_DIR = "/app/papers"
INDEX = os.path.join(PAPERS_DIR, "index.html")
PAPER_LINKS = "/app/paper_links.json"
URLS_TSV = "/app/urls.tsv"


def escape(s):
    return s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")


def expected_mapping():
    """Return list of (pid, expected_url) for every paper listed in the index."""
    if not os.path.isfile(INDEX):
        raise RuntimeError("missing paper index: %s" % INDEX)
    import re
    html = open(INDEX, encoding="utf-8").read()
    # rows: <tr data-pid="..." ...><a class="detail" href="PID.html">
    rows = re.findall(r'data-pid="([^"]+)"', html)
    result = []
    for pid in rows:
        result.append((pid, resolve_paper(pid)))
    # Preserve index order and drop nothing: return dict also
    return rows, dict(result)


def resolve_paper(pid):
    detail = os.path.join(PAPERS_DIR, pid + ".html")
    if not os.path.isfile(detail):
        return ""  # draft listed in index but no detail page -> unresolvable
    import re
    html = open(detail, encoding="utf-8").read()
    aff = ""
    m = re.search(r'<div class="affiliation">([^<]*)</div>', html)
    if m:
        aff = escape(m.group(1).strip())
    if aff == "":
        return ""  # no affiliation -> no author-owned repo can be identified
    official = None
    for href in re.findall(r'<a class="repo" href="([^"]+)"', html):
        u = urlsplit(href)
        if u.scheme == "https" and (u.netloc or "").lower() == "github.com":
            owner = (href.split("github.com/", 1)[1].split("/", 1)[0]
                     if "github.com/" in href else "")
            if owner == aff:
                official = href
                break
    if official is None:
        return ""
    return canonical.canonicalize(official)


def main():
    failures = []
    rows, mapping = expected_mapping()

    if not os.path.isfile(PAPER_LINKS):
        failures.append("missing /app/paper_links.json")
    else:
        agent = {}
        try:
            for i, line in enumerate(open(PAPER_LINKS, encoding="utf-8")):
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                agent[rec["id"]] = rec["url"]
        except Exception as e:
            failures.append("paper_links.json invalid: %s" % e)
            agent = {}

        missing = [pid for pid in mapping if pid not in agent]
        if missing:
            failures.append("paper_links missing entries: %r" % missing)
        for pid, want in mapping.items():
            got = agent.get(pid)
            if got is None:
                continue
            if got != want:
                failures.append("paper %s: got %r want %r" % (pid, got, want))
        extra = [pid for pid in agent if pid not in mapping]
        if extra:
            failures.append("paper_links has unknown ids: %r" % extra)

    # urls.tsv must contain exactly the canonical URLS of all resolved repos,
    # already canonicalized.
    expected_repos = sorted({u for u in mapping.values() if u})
    if not os.path.isfile(URLS_TSV):
        failures.append("missing %s" % URLS_TSV)
    else:
        tsv = [ln.strip() for ln in open(URLS_TSV, encoding="utf-8").read().split("\n")
               if ln.strip() != ""]
        if sorted(tsv) != expected_repos:
            failures.append("urls.tsv repos %r != expected %r"
                            % (sorted(tsv), expected_repos))
        for ln in tsv:
            if canonical.canonicalize(ln) != ln:
                failures.append("urls.tsv entry not canonical: %r" % ln)

    if failures:
        for f in failures:
            print("FAIL: %s" % f)
        sys.exit(1)
    print("PAPERS-OK (%d papers)" % len(mapping))
    sys.exit(0)


if __name__ == "__main__":
    main()