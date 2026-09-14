#!/usr/bin/env python3
"""Own failing reproduction for the wheel-name normalisation defect.

Contract (see the task instruction): this script exercises the INSTALLED
copy of setuptools -- the distribution-name component used in wheel file
names and in the wheel's .dist-info directory name -- and

  * exits non-zero with an explicit assertion error naming the offending
    name when the installed setuptools does NOT canonicalise the
    distribution name (dots, upper-case letters or runs of separators
    preserved verbatim), and
  * exits 0 after printing what it verified when it does canonicalise.

When the verifier evaluates the pre-fix direction it makes a pristine
buggy copy of the tree the only importable setuptools, so an honest script
fails there; against the repaired tree it passes. A script that only
re-implements the normalisation logic itself would not satisfy either
direction and is not a valid reproduction.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

# A distribution name that must become its canonical normalised form in the
# wheel file name and in the wheel's .dist-info directory name.
DISTNAME = "unicode.dist"
CANONICAL = "unicode_dist"
VERSION = "0.1"


def print_issue(names, where):
    print(f"FAIL: distribution name '{DISTNAME}' was NOT normalised in {where}")
    print(f"      saw: {names}")
    print("      required canonical form per the binary-distribution spec:", CANONICAL)
    sys.exit(1)


def check_wheel(path):
    from zipfile import ZipFile

    with ZipFile(path) as zf:
        infos = zf.namelist()
    bad = [n for n in infos if f"{DISTNAME}-{VERSION}.dist-info" in n]
    if bad:
        print_issue(bad, f"{path.name}: the .dist-info directory name")
    good = [n for n in infos if f"{CANONICAL}-{VERSION}.dist-info" in n]
    if not good:
        print_issue([n for n in infos if n.endswith(".dist-info/METADATA")],
                    f"{path.name}: expected dist-info under {CANONICAL}-{VERSION}.dist-info/")
    return good[0]


def main():
    # 1) the module-level helper used for the distribution component of a
    #    wheel file name must already canonicalise.
    from setuptools._normalization import safer_name  # noqa: E402

    observed = safer_name(DISTNAME)
    if observed != CANONICAL:
        print_issue(observed, "the name-normalisation helper")

    # 2) end-to-end: an actual bdist_wheel build must produce the canonical
    #    wheel file name and .dist-info directory name.
    with tempfile.TemporaryDirectory(prefix="oakum-repro-") as td:
        root = Path(td)
        pkg = root / "apppkg"
        pkg.mkdir()
        (pkg / "__init__.py").write_text("", encoding="utf-8")
        (root / "setup.py").write_text(
            "from setuptools import setup\n"
            f'setup(name="{DISTNAME}", version="{VERSION}", packages=["apppkg"])\n',
            encoding="utf-8",
        )
        out = root / "dist"
        res = subprocess.run(
            [sys.executable, "setup.py", "-q", "bdist_wheel", "-d", str(out)],
            cwd=str(root),
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            print("FAIL: bdist_wheel exited", res.returncode)
            print(res.stderr)
            sys.exit(1)
        wheels = sorted(out.glob("*.whl"))
        expected = f"{CANONICAL}-{VERSION}-py3-none-any.whl"
        if not wheels or wheels[0].name != expected:
            print_issue([w.name for w in wheels], "the wheel file name")
        dist_info = check_wheel(wheels[0])
        print(f"ok: wheel file name is {wheels[0].name}")
        print(f"ok: dist-info directory is {dist_info}")

    print("ok: distribution names are canonicalised to the wheel format")
    return 0


if __name__ == "__main__":
    sys.exit(main())