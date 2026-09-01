#!/usr/bin/env python3
"""Independent verifier helper for echo-dial.

Usage: check.py <output_dir> <expected.json>

Validates that <output_dir> contains exactly the artifacts name.txt,
plaintexts.txt and word.txt and that each matches the corresponding field of
<expected.json> ({"names": [...], "plaintexts": [...], "word": "..."}).

Exit 0 on full match, non-zero otherwise.
"""
import json
import os
import sys


def main():
    outdir, expf = sys.argv[1], sys.argv[2]
    with open(expf, "r", encoding="utf-8") as fh:
        exp = json.load(fh)
    ok = True

    def check(fname, bits):
        nonlocal ok

        path = os.path.join(outdir, fname)
        if not os.path.exists(path):
            print("check.py: FAIL missing %s" % path)
            ok = False
            return
        with open(path, "r", encoding="utf-8") as fh:
            got = fh.read()
        if not got.endswith("\n"):
            print("check.py: FAIL %s has no trailing newline" % fname)
            ok = False
            return
        got = got[:-1] if got.endswith("\n") else got
        if got != bits:
            print("check.py: FAIL %s mismatch" % fname)
            print("  expected=%r" % bits)
            print("  got     =%r" % got)
            ok = False

    check("name.txt", "\n".join(exp["names"]))
    check("plaintexts.txt", "\n".join(exp["plaintexts"]))
    check("word.txt", exp["word"])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
