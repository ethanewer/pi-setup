#!/usr/bin/env python3
"""Hidden case 3: sdist of a setup.cfg-declared version "1.0.0" (legacy
metadata mechanism, triple-zero release) must keep the full version in the
archive name."""
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(tempfile.mkdtemp(prefix="rbp-h3-"))
(root / "src" / "h3pack").mkdir(parents=True)
(root / "src" / "h3pack" / "__init__.py").write_text("VALUE = 7\n")
(root / "setup.py").write_text("from setuptools import setup\nsetup()\n")
(root / "setup.cfg").write_text(
    "[metadata]\nname = h3pack\nversion = 1.0.0\n"
    "[options]\npackage_dir= = src\npackages = find:\n"
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
print("dist files:", names)
if not (root / "dist" / "h3pack-1.0.0.tar.gz").is_file():
    print(f"FAIL: h3pack-1.0.0.tar.gz not produced (got {names!r})")
    sys.exit(1)
if (root / "dist" / "h3pack-1.tar.gz").exists():
    print("FAIL: collapsed archive name h3pack-1.tar.gz was produced")
    sys.exit(1)
print("OK hidden-case-3")