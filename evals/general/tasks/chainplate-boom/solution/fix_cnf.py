#!/usr/bin/env python3
"""Apply the CNF terminal-sibling fix to nltk/tree/transforms.py.

Pre-fix, the binarization step of chomsky_normal_form reads a label from
every child of a node that has more than two children
(`childNodes = [child.label() for child in node]`), so a plain terminal
among the children -- a word, punctuation such as '+', or a non-string value
such as the integer 7 -- raises AttributeError.  The fixed line builds the
intermediate node names from tree children's labels and the terminals' own
string values.  Idempotent; exits non-zero if the expected (pre-fix or
already-fixed) code is missing.
"""

import sys
from pathlib import Path

OLD = "                childNodes = [child.label() for child in node]"
NEW = """                childNodes = [
                    str(child.label()) if isinstance(child, Tree) else str(child)
                    for child in node
                ]"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_cnf.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")
    if NEW in src:
        print("transforms.py already carries the terminal-safe binarization")
        return 0
    if OLD not in src:
        print("FATAL: expected pre-fix binarization code not found", file=sys.stderr)
        return 1
    src = src.replace(OLD, NEW, 1)
    path.write_text(src, encoding="utf-8")
    print("applied terminal-safe binarization to transforms.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())