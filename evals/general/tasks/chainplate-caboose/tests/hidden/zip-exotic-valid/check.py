#!/usr/bin/env python3
"""chainplate-caboose hidden case: zip members with perfectly safe but exotic
names (spaces, non-ASCII letters, deep nesting) must still extract with exact
content, while backslash-relative escape names mixed into the same archive are
skipped. Passing the upstream regression tests alone is not enough here: an
over-broad "skip everything" fix fails this case, and so does a fix that only
catches the exact upstream name spellings.

Exit 0 on success; prints a readable failure otherwise.
"""
import os
import shutil
import tempfile
import zipfile

from setuptools.archive_util import unpack_archive

UNSAFE_NAMES = [
    r"safe\..\..\evil.txt",   # backslashes inside a relative path
    r"..\..\deep-evil.txt",   # backslash-relative escape, deeper
]
SAFE_NAMES = [
    "dir with space/ümläut-файл.txt",
    "dir with space/半角/日本語.txt",
    "a/b/c/d.txt",
    "top.txt",
]


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="cc-hidden-zip-exotic-")
    try:
        archive = os.path.join(tmp, "mixed.zip")
        with zipfile.ZipFile(archive, mode="w") as zf:
            for name in UNSAFE_NAMES + SAFE_NAMES:
                info = zipfile.ZipInfo()
                info.filename = name
                zf.writestr(info, name.encode())

        dest = os.path.join(tmp, "dest")
        unpack_archive(archive, dest)

        top = set(os.listdir(tmp))
        if top != {"mixed.zip", "dest"}:
            print(f"FAIL: unexpected entries in unpack root: {sorted(top)}")
            return 1

        got = sorted(
            os.path.relpath(os.path.join(r, f), dest)
            for r, _d, fs in os.walk(dest) for f in fs
        )
        if got != sorted(SAFE_NAMES):
            print(f"FAIL: extracted members are {got}, expected {sorted(SAFE_NAMES)}")
            return 1

        for name in SAFE_NAMES:
            with open(os.path.join(dest, name), "rb") as fh:
                if fh.read() != name.encode():
                    print(f"FAIL: {name!r} content corrupted")
                    return 1

        print(f"ok: zip-exotic-valid ({len(SAFE_NAMES)} safe members byte-exact, {len(UNSAFE_NAMES)} escapes skipped)")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())