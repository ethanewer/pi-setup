#!/usr/bin/env python3
"""Consumer-side artifact gate for the curlew pipeline."""
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def main():
    for name in ("bundle.zip", "manifest.json"):
        if not (ROOT / name).is_file():
            raise SystemExit("missing artifact file: %s" % name)
    manifest = json.loads((ROOT / "manifest.json").read_text())
    assert manifest["bundle"] == "bundle.zip", manifest
    assert manifest["stages"] == ["build", "package"], manifest
    with zipfile.ZipFile(ROOT / "bundle.zip") as zf:
        names = set(zf.namelist())
    expected = {"window.whl", "meta.json"}
    missing = sorted(expected - names)
    if missing:
        raise SystemExit("bundle missing members: %s" % missing)
    print("artifact ok: bundle=%s" % sorted(names))


if __name__ == "__main__":
    main()
