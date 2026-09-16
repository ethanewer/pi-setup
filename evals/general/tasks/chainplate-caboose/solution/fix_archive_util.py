#!/usr/bin/env python3
"""Apply the minimal upstream fix for the chainplate-caboose bug.

setuptools/archive_util.py's traversal guard splits archive member names on
'/' alone, so members whose names use a backslash instead of a slash (or
carry a drive letter or UNC prefix) pass the '..' check: on Windows such a
name resolves outside the extraction directory, on POSIX it lands as a
surprising literal backslash name. The fix funnels both the zip and tar
drivers through one `_resolve_dest` helper that rejects backslash,
drive-qualified and UNC names and, as defense in depth, confirms via
os.path.commonpath that the resolved destination really is inside the
extraction directory. Unsafe members are skipped; safe ones still extract.

The helper's source is read from /solution/resolve_dest_impl.py so it is
spliced in without string-escaping accidents.

Usage: fix_archive_util.py /app/src/setuptools/archive_util.py
"""
import importlib.util
import io
import os
import pathlib
import sys
import tarfile
import tempfile
import zipfile


def region(text: str, start_marker: str, end_marker: str) -> str:
    """Return the exact text from start_marker through end_marker."""
    i = text.index(start_marker)
    j = text.index(end_marker, i) + len(end_marker)
    return text[i:j]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_archive_util.py <path-to-archive_util.py>")
        return 2
    path = pathlib.Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")

    # 1. add the ntpath import
    OLD_IMP = "import contextlib\nimport os\n"
    NEW_IMP = "import contextlib\nimport ntpath\nimport os\n"
    if text.count(OLD_IMP) != 1 or text.count(NEW_IMP) == 1:
        print("ERROR: import block not in the expected buggy shape", file=sys.stderr)
        return 1
    text = text.replace(OLD_IMP, NEW_IMP)

    # 2. splice in the _resolve_dest helper after default_filter
    anchor = "    return dst\n\n\ndef unpack_archive("
    if text.count(anchor) != 1:
        print("ERROR: default_filter anchor not found", file=sys.stderr)
        return 1
    helper_path = pathlib.Path("/solution/resolve_dest_impl.py")
    if not helper_path.exists():
        helper_path = pathlib.Path(__file__).parent / "resolve_dest_impl.py"
    helper_src = helper_path.read_text(encoding="utf-8")
    helper_src = helper_src[helper_src.index("def _resolve_dest"):]
    text = text.replace(anchor, "    return dst\n\n\n" + helper_src + "\ndef unpack_archive(")

    # 3. zip driver: route through _resolve_dest
    old_zip = region(
        text,
        "        # don't extract absolute paths or ones with .. in them",
        "        target = progress_filter(name, target)",
    )
    if old_zip.count("'..' in name.split('/')") != 1:
        print("ERROR: zip guard not in the expected buggy shape", file=sys.stderr)
        return 1
    new_zip = (
        "        # don't extract members that escape the extraction directory\n"
        "        target = _resolve_dest(extract_dir, name)\n"
        "        if target is None:\n"
        "            continue\n"
        "\n"
        "        target = progress_filter(name, target)"
    )
    text = text.replace(old_zip, new_zip)

    # 4. tar driver: route through _resolve_dest
    old_tar = region(
        text,
        "            name = member.name\n            # don't extract absolute paths or ones with .. in them",
        "            prelim_dst = os.path.join(extract_dir, *name.split('/'))",
    )
    if old_tar.count("'..' in name.split('/')") != 1:
        print("ERROR: tar guard not in the expected buggy shape", file=sys.stderr)
        return 1
    new_tar = (
        "            name = member.name\n"
        "            # don't extract members that escape the extraction directory\n"
        "            prelim_dst = _resolve_dest(extract_dir, name)\n"
        "            if prelim_dst is None:\n"
        "                continue"
    )
    text = text.replace(old_tar, new_tar)

    path.write_text(text, encoding="utf-8")
    print("patched: archive extraction now funnels through _resolve_dest()")
    return 0


if __name__ == "__main__":
    sys.exit(main())