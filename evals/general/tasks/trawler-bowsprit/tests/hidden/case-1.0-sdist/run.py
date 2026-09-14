#!/usr/bin/env python3
"""Hidden case 1: sdist of a pyproject-declared version "1.0" must keep the
full version in the archive name (upstream regression test only covers the
default version 0.0.0; this exercises a declared trailing-zero version)."""
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(tempfile.mkdtemp(prefix="rbp-h1-"))
(root / "src" / "h1pack").mkdir(parents=True)
(root / "src" / "h1pack" / "__init__.py").write_text("VALUE = 42\n")
(root / "pyproject.toml").write_text(
    '[project]\nname = "h1pack"\nversion = "1.0"\n'
    '[build-system]\nrequires = []\nbuild-backend = "setuptools.build_meta"\n'
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
if not (root / "dist" / "h1pack-1.0.tar.gz").is_file():
    print(f"FAIL: h1pack-1.0.tar.gz not produced (got {names!r})")
    sys.exit(1)
if (root / "dist" / "h1pack-1.tar.gz").exists():
    print("FAIL: collapsed archive name h1pack-1.tar.gz was produced")
    sys.exit(1)
print("OK hidden-case-1")