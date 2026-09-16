#!/usr/bin/env python3
"""Hidden case 2: release-name strings must round-trip a matrix of declared
versions verbatim (trailing zeros, pre-release, release-candidate, plain)."""
import sys

from setuptools import Distribution

CASES = [
    ("0.0.0", "0.0.0"),     # setuptools' default version
    ("1.0", "1.0"),         # oracle value from the upstream issue
    ("2.3.0", "2.3.0"),
    ("1.0b1", "1.0b1"),     # pre-release on a trailing-zero release
    ("3.0.0rc1", "3.0.0rc1"),
    ("2024.4.13", "2024.4.13"),
]

bad = []
for version, expected in CASES:
    got = Distribution({"name": "h2pack", "version": version}).get_fullname()
    want = f"h2pack-{expected}"
    print(f"version={version!r:12} -> {got!r}")
    if got != want:
        bad.append((version, got, want))
if bad:
    for version, got, want in bad:
        print(f"FAIL version {version!r}: got {got!r}, expected {want!r}")
    sys.exit(1)
print("OK hidden-case-2")