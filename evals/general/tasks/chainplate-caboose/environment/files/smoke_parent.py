#!/usr/bin/env python3
"""Build-time smoke for chainplate-caboose.

Fails the image build unless the mined buggy state is present:
  1. the editable install resolves `setuptools` to /app/src;
  2. setuptools/archive_util.py still has the old '/' -only traversal guards
     and no _resolve_dest helper (i.e. the buggy parent state);
  3. the direct reproduction extracts BOTH members (the bug is live);
  4. the project's own regression tests (overlaid from the upstream fix
     commit into setuptools/tests/test_archive_util.py) fail inside the
     image with the mined summary '7 failed, 7 passed, 1 xpassed'.

This file is built into the image, so it is visible to the agent; it holds
no answer. It only re-proves the starting state.
"""
import io
import os
import subprocess
import sys
import tarfile
import tempfile

SRC = "/app/src"


def run(cmd, cwd=None):
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=600
    )


def main() -> int:
    problems = []

    # 1. editable install resolves to the working tree
    import setuptools
    if os.path.dirname(setuptools.__file__) != f"{SRC}/setuptools":
        problems.append(f"setuptools resolves to {setuptools.__file__}, expected {SRC}/setuptools")

    # 2. buggy guards present, no fix helper
    with open(f"{SRC}/setuptools/archive_util.py", encoding="utf-8") as fh:
        src = fh.read()
    if "'..' in name.split('/')" not in src:
        problems.append("old '/' -only traversal guard not found in archive_util.py")
    if src.count("_resolve_dest") != 0:
        problems.append("archive_util.py already contains _resolve_dest")

    # 3. direct reproduction: both members extracted (bug is live)
    tmp = tempfile.mkdtemp()
    tgz = os.path.join(tmp, "malicious.tar.gz")
    with tarfile.open(tgz, mode="w:gz") as t:
        for name in ["..\\escaped.txt", "inside.txt"]:
            info = tarfile.TarInfo(name)
            data = name.encode()
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))
    dest = os.path.join(tmp, "dest")
    from setuptools import archive_util
    archive_util.unpack_archive(tgz, dest)
    names = sorted(
        os.path.relpath(os.path.join(r, f), dest)
        for r, _d, fs in os.walk(dest) for f in fs
    )
    if names != ["..\\escaped.txt", "inside.txt"]:
        problems.append(f"direct repro did not leak both members: {names!r}")

    # 4. project's own regression tests fail with the mined summary
    proc = run(
        [sys.executable, "-m", "pytest", "-q", "setuptools/tests/test_archive_util.py"],
        cwd=SRC,
    )
    out = proc.stdout + proc.stderr
    if "7 failed, 7 passed, 1 xpassed" not in out:
        problems.append(
            f"golden tests did not show '7 failed, 7 passed, 1 xpassed' "
            f"(rc={proc.returncode}); tail:\n{out[-1500:]}"
        )

    if problems:
        for p in problems:
            print("SMOKE FAIL:", p, file=sys.stderr)
        return 1
    print("SMOKE OK: parent state confirmed (bug live, golden overlay failing as mined)")
    return 0


if __name__ == "__main__":
    sys.exit(main())