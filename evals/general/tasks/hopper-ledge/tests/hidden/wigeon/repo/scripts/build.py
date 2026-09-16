#!/usr/bin/env python3
"""Assemble the wigeon wheel and sidecar artifacts into out/."""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".cache_deps"))
import sndlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
APP = ROOT / "wigeon"
OUT = ROOT / "out"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(APP.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert sndlib.tag() == "vendored-0.9.0", "dependency mismatch"
    OUT.mkdir(exist_ok=True)
    wheel = OUT / "wigeon.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(APP.rglob("*.py")):
            zf.write(f, f.relative_to(APP).as_posix())
        zf.writestr("VERSION", "2.1.0\n")
    (OUT / "sources.sha256").write_text(sources_digest() + "\n")
    (OUT / "metadata.json").write_text(json.dumps({
        "package": "wigeon",
        "version": "2.1.0",
        "wheel": "wigeon.whl",
        "sndlib": sndlib.tag(),
    }, indent=2))
    print("built out/wigeon.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
