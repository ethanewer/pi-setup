#!/usr/bin/env python3
"""Assemble the curlew wheel and sidecar artifacts into dist/."""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".vendor"))
import gridlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
LIB = ROOT / "curlew"
DIST = ROOT / "dist"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(LIB.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert gridlib.tag() == "vendored-0.4.1", "dependency mismatch"
    DIST.mkdir(exist_ok=True)
    wheel = DIST / "window.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(LIB.rglob("*.py")):
            zf.write(f, f.relative_to(LIB).as_posix())
        zf.writestr("VERSION", "0.3.4\n")
    (DIST / "checksums.txt").write_text("sha256 " + sources_digest() + "\n")
    (DIST / "meta.json").write_text(json.dumps({
        "package": "curlew", "version": "0.3.4", "wheel": "window.whl",
        "gridlib": gridlib.tag(),
    }, indent=2))
    print("built dist/window.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
