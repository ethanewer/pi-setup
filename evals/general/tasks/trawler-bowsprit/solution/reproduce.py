#!/usr/bin/env python3
"""Reproduction for trawler-bowsprit (setuptools artifact-name version loss).

Exits non-zero while the bug is present (any setuptools whose release names
collapse the declared version) and 0 once artifact names preserve the
declared version exactly. Exercises both the release-name strings and a
real source-distribution build.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from setuptools import Distribution

# (declared version, expected release-name suffix)
CASES = [
    ("0.0.0", "0.0.0"),
    ("1.0", "1.0"),
    ("2.3.0", "2.3.0"),
    ("1.0b1", "1.0b1"),
]

fails = []
for version, expected in CASES:
    full = Distribution({"name": "rbp-demo", "version": version}).get_fullname()
    want = f"rbp_demo-{expected}"
    print(f"version={version!r:10} fullname={full!r}")
    if full != want:
        fails.append(f"version {version!r}: fullname {full!r}, expected {want!r}")

# Real sdist build: default version must survive into the archive name.
root = Path(tempfile.mkdtemp(prefix="rbp-repro-"))
(src := root / "src" / "rbp_demo").mkdir(parents=True)
(src / "__init__.py").write_text("VALUE = 1\n")
(root / "pyproject.toml").write_text(
    "[project]\nname = \"rbp-demo\"\nversion = \"1.0\"\n"
    "[build-system]\nrequires = []\nbuild-backend = \"setuptools.build_meta\"\n"
)
r = subprocess.run(
    [sys.executable, "-m", "build", "--no-isolation", "--sdist", str(root)],
    capture_output=True,
    text=True,
)
if r.returncode != 0:
    print(r.stdout + r.stderr)
    sys.exit(2)
names = sorted(p.name for p in (root / "dist").iterdir())
print("sdist dist/:", names)
if not (root / "dist" / "rbp_demo-1.0.tar.gz").is_file():
    fails.append(f"sdist archive name: {names!r}, expected rbp_demo-1.0.tar.gz")
if (root / "dist" / "rbp_demo-1.tar.gz").exists():
    fails.append("collapsed sdist archive name rbp_demo-1.tar.gz was produced")

if fails:
    print("\nBUG PRESENT:")
    for f in fails:
        print(" -", f)
    sys.exit(1)
print("\nok: artifact names preserve the declared version")
sys.exit(0)