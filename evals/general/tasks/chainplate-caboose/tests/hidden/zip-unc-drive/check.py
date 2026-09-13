#!/usr/bin/env python3
"""chainplate-caboose hidden case: zip members named with UNC prefixes,
drive-letter-plus-backslash paths and bare drive letters must be skipped,
while a control member of the same archive is still extracted.

The upstream regression tests cover '..\\escaped.txt' style names and the
bare drive form 'C:escaped.txt', but not UNC prefixes, path-style drive
names, or a second drive letter; those extra forms are what this case adds.

Runs against the installed (editable) setuptools, i.e. the agent's repair of
/app/src. Exit 0 on success; prints a readable failure otherwise.
"""
import os
import shutil
import tempfile
import zipfile

from setuptools.archive_util import unpack_archive

UNSAFE_NAMES = [
    r"\\server\share\evil.txt",   # UNC prefix
    r"C:\windows\evil.txt",       # drive letter + backslash path
    "D:evil.txt",                 # bare drive letter, second drive
]
CONTROL = "control.txt"


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="cc-hidden-zip-unc-")
    try:
        archive = os.path.join(tmp, "malicious.zip")
        with zipfile.ZipFile(archive, mode="w") as zf:
            for name in UNSAFE_NAMES + [CONTROL]:
                info = zipfile.ZipInfo()
                info.filename = name
                zf.writestr(info, name.encode())

        dest = os.path.join(tmp, "dest")
        unpack_archive(archive, dest)

        # nothing may exist outside dest except the archive itself
        top = set(os.listdir(tmp))
        if top != {"malicious.zip", "dest"}:
            print(f"FAIL: unexpected entries in unpack root: {sorted(top)}")
            return 1

        # no leaked literal backslash / drive-letter members may remain
        leaked = sorted(
            os.path.relpath(os.path.join(r, f), dest)
            for r, _d, fs in os.walk(dest) for f in fs
        )
        if leaked != [CONTROL]:
            print(f"FAIL: extracted members are {leaked}, expected only {[CONTROL]}")
            return 1

        # the control member kept its exact content
        with open(os.path.join(dest, CONTROL), encoding="utf-8") as fh:
            if fh.read() != CONTROL:
                print("FAIL: control member content corrupted")
                return 1

        print(f"ok: zip-unc-drive ({len(UNSAFE_NAMES)} unsafe names skipped, {CONTROL!r} extracted)")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())