#!/usr/bin/env python3
"""Minimal fix for trawler-grove: normalize explicit ref pins before checkout.

_Git's clone fallback computes the revision to check out and then never
strips leading refs/heads/ or refs/tags/ prefixes, because the two
`revision.replace(...)` calls discard their results (str.replace returns a
new string) and the first prefix is misspelled "refs/head/". The result is
that a git dependency pinned to an explicit plumbing ref is handed to
`git checkout` unchanged and the clone fails or lands on the wrong revision.

This applies exactly the upstream fix: assign the removeprefix results.
"""
from __future__ import annotations

import re
import sys


def patch(path: str) -> bool:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()

    old1 = '            revision.replace("refs/head/", "")'
    new1 = '            revision = revision.removeprefix("refs/heads/")'
    old2 = '            revision.replace("refs/tags/", "")'
    new2 = '            revision = revision.removeprefix("refs/tags/")'

    if text.count(old1) != 1 or text.count(old2) != 1:
        raise SystemExit(
            f"unexpected source shape: expected one occurrence of each buggy "
            f"line ({text.count(old1)}, {text.count(old2)})"
        )

    patched = text.replace(old1, new1).replace(old2, new2)

    # Belt: the buggy discarded-call lines are gone and the fixed lines are
    # assigned to the revision variable.
    if "revision.replace(" in patched:
        raise SystemExit("still a discarded revision.replace call in source")
    if not re.search(r'revision = revision\.removeprefix\("refs/heads/"\)', patched):
        raise SystemExit("fixed heads line not present")
    if not re.search(r'revision = revision\.removeprefix\("refs/tags/"\)', patched):
        raise SystemExit("fixed tags line not present")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(patched)
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_backend.py <backend.py>")
    patch(sys.argv[1])
    print(f"patched {sys.argv[1]}")