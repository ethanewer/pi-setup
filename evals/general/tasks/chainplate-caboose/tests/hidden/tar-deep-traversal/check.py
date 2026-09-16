#!/usr/bin/env python3
"""chainplate-caboose hidden case: a tar whose members mix deep '..' chains,
backslash-relative names with backslashes INSIDE nested relative paths, and
legitimate nested files plus a directory member. The safe members must land
byte-exactly; every traversal-shaped member must be skipped, on any platform.

The upstream regression tests cover shallow '../x', 'sub/../../x' and
'..\\x'-style names; this case adds deeper '..' chains, '\\'-separated
components inside what looks like a relative path, and a real directory
member ('pkg/conf/') to prove directory handling still works.

Exit 0 on success; prints a readable failure otherwise.
"""
import io
import os
import shutil
import tarfile
import tempfile

from setuptools.archive_util import unpack_archive

UNSAFE_NAMES = [
    "a/b/../../../../../../../leak.txt",  # very deep '..' chain
    r"..\..\leak.txt",                    # dotted backslash-relative
    r"x\y\..\..\leak.txt",                # backslashes inside a relative path
]
SAFE_TREE = {
    "pkg/data.txt": b"package data 1\n",
    "pkg/conf/deep.txt": b"level=3\n",
}


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="cc-hidden-tar-deep-")
    try:
        archive = os.path.join(tmp, "malicious.tar.gz")
        with tarfile.open(archive, mode="w:gz") as t:
            for name in UNSAFE_NAMES:
                info = tarfile.TarInfo(name)
                data = name.encode()
                info.size = len(data)
                t.addfile(info, io.BytesIO(data))
            for name, payload in SAFE_TREE.items():
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                t.addfile(info, io.BytesIO(payload))
            # an explicit directory member
            info = tarfile.TarInfo("pkg/conf/")
            info.size = 0
            info.type = tarfile.DIRTYPE
            t.addfile(info)

        dest = os.path.join(tmp, "dest")
        unpack_archive(archive, dest)

        top = set(os.listdir(tmp))
        if top != {"malicious.tar.gz", "dest"}:
            print(f"FAIL: unexpected entries in unpack root: {sorted(top)}")
            return 1

        got = sorted(
            os.path.relpath(os.path.join(r, f), dest)
            for r, _d, fs in os.walk(dest) for f in fs
        )
        expect = sorted(SAFE_TREE)
        if got != expect:
            print(f"FAIL: extracted members are {got}, expected {expect}")
            return 1

        for name, payload in SAFE_TREE.items():
            with open(os.path.join(dest, name), "rb") as fh:
                if fh.read() != payload:
                    print(f"FAIL: {name!r} content corrupted")
                    return 1

        print(f"ok: tar-deep-traversal ({len(UNSAFE_NAMES)} unsafe names skipped, safe tree intact)")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())