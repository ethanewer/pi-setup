#!/usr/bin/env python3
"""Assemble the avocet wheel and sidecar artifacts into artifacts/."""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".deps"))
import statlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
PKG = ROOT / "avocet"
OUT = ROOT / "artifacts"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(PKG.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert statlib.tag() == "vendored-2.0.0", "dependency mismatch"
    OUT.mkdir(exist_ok=True)
    wheel = OUT / "avocet.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(PKG.rglob("*.py")):
            zf.write(f, f.relative_to(PKG).as_posix())
        zf.writestr("VERSION", "0.7.2\n")
    (OUT / "sources.sha256").write_text(sources_digest() + "\n")
    (OUT / "metadata.json").write_text(json.dumps({
        "package": "avocet", "version": "0.7.2", "wheel": "avocet.whl",
        "statlib": statlib.tag(),
    }, indent=2))
    print("built artifacts/avocet.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
