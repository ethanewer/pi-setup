#!/usr/bin/env python3
"""Probe for capstan-boom: drive semgrep's real URL conversion on a set of
git remotes and compare each result against the correct https form.

A remote written in scp-like shorthand (user@host:owner/repo with a dash in
the owner or repo name and no trailing ".git") must be converted to its https
form; a remote that already works (explicit protocol, trailing ".git", plain
owner/repo) must keep working.

Exits 0 only when every case converts correctly; while the bug is present it
prints the mismatches and exits 1.
"""

import sys

from semgrep.meta import get_url_from_sstp_url

# (input remote, expected https URL)
CASES = [
    # scp-like, no protocol, no trailing .git, dash in owner and repo
    (
        "git@code1.somecompany.internal:somecompany-eval/owasp-juice-shop",
        "https://code1.somecompany.internal/somecompany-eval/owasp-juice-shop",
    ),
    # scp-like, dash in owner only, trailing .git
    (
        "git@code3.somecompany.internal:eval/owasp-juice-shop.git",
        "https://code3.somecompany.internal/eval/owasp-juice-shop",
    ),
    # scp-like, no dash: already worked, must keep working
    ("git@github.com:semgrep/semgrep", "https://github.com/semgrep/semgrep"),
    # explicit protocol with .git: already worked, must keep working
    (
        "https://gitlab.com/example/group2/group3/test-case.git",
        "https://gitlab.com/example/group2/group3/test-case",
    ),
]

bad = 0
for url, expected in CASES:
    got = get_url_from_sstp_url(url)
    if got == expected:
        print(f"[ok] {url!r} -> {got!r}")
    else:
        bad += 1
        print(f"[MISMATCH] {url!r}")
        print(f"    expected: {expected!r}")
        print(f"    got:      {got!r}")

if bad:
    print(f"\n{len(CASES) - bad}/{len(CASES)} cases correct; "
          f"{bad} conversion(s) wrong: the bug is present.")
    sys.exit(1)

print(f"\nall {len(CASES)} cases convert correctly")
sys.exit(0)