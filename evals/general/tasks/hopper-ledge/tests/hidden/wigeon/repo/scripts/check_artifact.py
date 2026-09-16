#!/usr/bin/env python3
"""Consumer-side artifact gate for the wigeon pipeline."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def sources_digest():
    h = hashlib.sha256()
    for f in sorted((ROOT / "wigeon").rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    for required in ("metadata.json", "wigeon.whl", "sources.sha256"):
        if not (ROOT / required).is_file():
            raise SystemExit("missing artifact file: %s" % required)
    meta = json.loads((ROOT / "metadata.json").read_text())
    assert meta["package"] == "wigeon", meta
    with zipfile.ZipFile(ROOT / "wigeon.whl") as zf:
        names = set(zf.namelist())
    expected = {"__init__.py", "core.py", "VERSION"}
    missing = sorted(expected - names)
    if missing:
        raise SystemExit("wheel missing members: %s" % missing)
    got = (ROOT / "sources.sha256").read_text().strip()
    want = sources_digest()
    if got != want:
        raise SystemExit("sources digest mismatch: %s != %s" % (got, want))
    print("artifact ok: wheel ok digest=%s" % want[:12])


if __name__ == "__main__":
    main()
