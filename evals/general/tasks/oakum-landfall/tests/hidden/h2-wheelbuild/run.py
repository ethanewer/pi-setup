#!/usr/bin/env python3
"""Hidden case h2 (end-to-end wheel builds).

Builds real wheels from scratch distributions whose names contain dots and
upper-case letters (inputs the upstream regression tests do not use) and
asserts that BOTH the wheel file name and the wheel's .dist-info directory
name use the canonical normalised distribution name. Fails at the pre-fix
tree (names written verbatim into the archive file names), passes once the
installed setuptools canonicalises on every path.
"""

import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

PROJECTS = {
    # distribution name -> (canonical name, version)
    "Camel.Case": ("camel_case", "0.1"),
    "weird.name--With--Dashes": ("weird_name_with_dashes", "0.1"),
}


def build_wheel(name, version, root):
    pkg = root / "pkg"
    pkg.mkdir()
    (pkg / "__init__.py").write_text("", encoding="utf-8")
    (root / "setup.py").write_text(
        "from setuptools import setup\n"
        f'setup(name="{name}", version="{version}", packages=["pkg"])\n',
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
        print(f"FAIL: bdist_wheel for {name!r} exited {res.returncode}")
        print(res.stderr)
        raise SystemExit(1)
    return sorted(out.glob("*.whl"))


def main():
    failures = []
    with tempfile.TemporaryDirectory(prefix="oakum-h2-") as td:
        base = Path(td)
        for i, (name, (canonical, version)) in enumerate(PROJECTS.items()):
            root = base / str(i)
            root.mkdir()
            wheels = build_wheel(name, version, root)
            expected = f"{canonical}-{version}-py3-none-any.whl"
            if not wheels or wheels[0].name != expected:
                failures.append(
                    f"wheel file name for {name!r}: got {[w.name for w in wheels]}, "
                    f"expected {expected!r}"
                )
                continue
            with ZipFile(wheels[0]) as zf:
                infos = zf.namelist()
            if not any(n.startswith(f"{canonical}-{version}.dist-info/") for n in infos):
                failures.append(
                    f".dist-info dir for {name!r}: expected prefix "
                    f"{canonical}-{version}.dist-info/, saw {[n for n in infos if n.endswith('/METADATA')][:3]}"
                )
            if any(f"{name}-{version}.dist-info/" in n for n in infos):
                failures.append(f"verbatim dist-info dir still present for {name!r}")
    if failures:
        for f in failures:
            print("FAIL:", f)
        raise SystemExit(1)
    print(f"ok: {len(PROJECTS)} end-to-end wheels have canonical file and dir names")


if __name__ == "__main__":
    main()