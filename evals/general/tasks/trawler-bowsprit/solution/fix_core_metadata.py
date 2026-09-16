#!/usr/bin/env python3
"""Apply the minimal upstream fix for trawler-bowsprit.

setuptools monkey-patches Distribution.get_fullname() in
setuptools/_core_metadata.py. At the parent commit that function runs the
declared version through packaging.utils.canonicalize_version() before
embedding it in the release name, so artifact basenames derived from the
full name lose version fidelity ("1.0" -> "1", "0.0.0" -> "0"). The upstream
fix (pypa/setuptools#4302, commit df45427cbb) keeps the canonicalized
project name but embeds self.get_version() verbatim.

Usage: fix_core_metadata.py /app/src/setuptools/_core_metadata.py
"""
import sys

IMPORT_BUGGY = "from .extern.packaging.utils import canonicalize_name, canonicalize_version"
IMPORT_FIXED = "from .extern.packaging.utils import canonicalize_name"

CALL_BUGGY = """        canonicalize_name(self.get_name()).replace('-', '_'),
        canonicalize_version(self.get_version()),
    )"""
CALL_FIXED = """            canonicalize_name(self.get_name()).replace('-', '_'),
            self.get_version(),
        )"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_core_metadata.py <path-to-setuptools/_core_metadata.py>")
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if IMPORT_BUGGY not in text:
        print(f"ERROR: expected import line not found in {path}; refusing to patch",
              file=sys.stderr)
        return 1
    if CALL_BUGGY not in text:
        print(f"ERROR: expected canonicalize_version call site not found in {path}; "
              f"refusing to patch", file=sys.stderr)
        return 1
    text = text.replace(IMPORT_BUGGY, IMPORT_FIXED).replace(CALL_BUGGY, CALL_FIXED)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("patched: get_fullname now embeds the declared version verbatim")
    return 0


if __name__ == "__main__":
    sys.exit(main())