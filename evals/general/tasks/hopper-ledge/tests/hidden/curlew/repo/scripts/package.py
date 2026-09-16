#!/usr/bin/env python3
"""Bundle the build artifact into a release archive for consumers."""
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def main():
    for name in ("window.whl", "meta.json", "checksums.txt"):
        if not (ROOT / name).is_file():
            raise SystemExit("missing build artifact: %s" % name)
    release = ROOT / "release"
    release.mkdir(exist_ok=True)
    with zipfile.ZipFile(release / "bundle.zip", "w",
                         zipfile.ZIP_DEFLATED) as zf:
        zf.write(ROOT / "window.whl", "window.whl")
        zf.write(ROOT / "meta.json", "meta.json")
    (release / "manifest.json").write_text(json.dumps({
        "bundle": "bundle.zip", "stages": ["build", "package"],
    }, indent=2))
    print("packaged release/bundle.zip")


if __name__ == "__main__":
    main()
