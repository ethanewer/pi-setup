#!/usr/bin/env python3
"""
corbel-weir oracle: repair the release metadata of the /app/src checkout so it
describes the upstream 8.5.0 release again, build sdist + wheel from the tree
(no build isolation, no network), install the wheel into a fresh clean venv
from disk, verify metadata/import/version, rebuild a wheel from the sdist, and
write /app/dist/release-proof.json.

This solver does the real work an agent must do; nothing here reads any
expectation file.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import venv
import zipfile

VERSION = "8.5.0"
SRC = pathlib.Path("/app/src")
DIST = pathlib.Path("/app/dist")
SDIST = DIST / f"click-{VERSION}.tar.gz"
WHEEL = DIST / f"click-{VERSION}-py3-none-any.whl"
PROOF = DIST / "release-proof.json"
VENV_DIR = pathlib.Path("/app/release-check-venv")
PYPROJECT = SRC / "pyproject.toml"


def run(cmd, **kw):
    print("+", " ".join(str(c) for c in cmd))
    return subprocess.run([str(c) for c in cmd], check=True, **kw)


def stream(cmd):
    return subprocess.run(
        [str(c) for c in cmd], check=True, capture_output=True, text=True
    ).stdout


def metadata_field(whl_or_dir, field):
    """Read a METADATA field out of a built wheel's dist-info."""
    with zipfile.ZipFile(whl_or_dir) as z:
        dist_info = next(
            n for n in z.namelist() if n.endswith(".dist-info/METADATA")
        )
        for line in z.read(dist_info).decode().splitlines():
            if line.startswith(field + ": "):
                return line.split(": ", 1)[1]
    return None


def main():
    # 1. Locate and repair the damaged release metadata: the project version
    #    must again describe the upstream 8.5.0 release.
    text = PYPROJECT.read_text()
    fixed, n = re.subn(
        r'^version\s*=\s*"[^"]+"',
        f'version = "{VERSION}"',
        text,
        count=1,
        flags=re.M,
    )
    if n != 1 or f'version = "{VERSION}"' not in fixed:
        raise SystemExit("FATAL: could not repair the project version metadata")
    PYPROJECT.write_text(fixed)
    print(f"repaired version metadata in {PYPROJECT}")

    # 2. Build sdist + wheel from the checkout. --no-isolation: the declared
    #    backend flit_core is installed in the image; nothing may be fetched.
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True)
    run(
        [
            "python3",
            "-m",
            "build",
            "--no-isolation",
            "--sdist",
            "--wheel",
            "--outdir",
            DIST,
            SRC,
        ]
    )
    for p in (SDIST, WHEEL):
        if not p.exists():
            raise SystemExit(f"FATAL: build did not produce {p}")

    # 3. Fresh, clean venv; install the wheel from disk, no network.
    if VENV_DIR.exists():
        shutil.rmtree(VENV_DIR)
    venv.EnvBuilder(with_pip=True, system_site_packages=False).create(VENV_DIR)
    py = VENV_DIR / "bin" / "python"
    run(
        [
            VENV_DIR / "bin" / "pip",
            "install",
            "--no-index",
            "--no-deps",
            WHEEL,
        ]
    )

    # 4. Prove the installed package: metadata, import surface, and the CLI
    #    version string a built tool reports.
    installed_version = stream([py, "-c", "import importlib.metadata as m; print(m.version('click'))"]).strip()
    import_ok = False
    probe = stream(
        [
            py,
            "-c",
            "import importlib.metadata as m, click;"
            "from click.testing import CliRunner;"
            "assert m.version('click') == '8.5.0';"
            "assert click.__version__ == '8.5.0';"
            "print('ok')",
        ]
    ).strip()
    import_ok = probe == "ok"
    if not import_ok:
        raise SystemExit("FATAL: installed wheel failed import/metadata probe")

    # 5. The sdist must be standalone: build a wheel from the sdist alone,
    #    and it must still be version 8.5.0.
    rb = pathlib.Path("/tmp/cw-oracle-rb")
    if rb.exists():
        shutil.rmtree(rb)
    rb.mkdir()
    run(
        [
            "python3",
            "-m",
            "build",
            "--no-isolation",
            "--wheel",
            "--outdir",
            rb,
            SDIST,
        ]
    )
    rb_wheels = sorted(rb.glob("click-*.whl"))
    if len(rb_wheels) != 1:
        raise SystemExit("FATAL: sdist rebuild did not produce exactly one wheel")
    sdist_rebuild_version = metadata_field(rb_wheels[0], "Version")
    if sdist_rebuild_version != VERSION:
        raise SystemExit(
            f"FATAL: sdist-rebuilt wheel version {sdist_rebuild_version!r}"
        )

    proof = {
        "version": VERSION,
        "installed_version": installed_version,
        "import_ok": import_ok,
        "venv_python": str(py),
        "wheel": str(WHEEL),
        "sdist_rebuild_version": sdist_rebuild_version,
    }
    PROOF.write_text(json.dumps(proof, indent=2) + "\n")
    print(f"proof written to {PROOF}")


if __name__ == "__main__":
    main()