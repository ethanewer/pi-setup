#!/usr/bin/env python3
"""Applies the boundary-containment fix to CharRange.java.

The bug: `contains(CharRange)` special-cases a negated *argument* only by
accepting it when the receiver spans the whole domain. A negated argument
denotes [0, start-1] union [end+1, MAX_VALUE]. When the excluded block
touches a domain boundary that set collapses to one interval (or the empty
set), and a proper receiver can contain it.

The fix replaces the negated-argument branch with explicit handling:
  - excluded [0, MAX_VALUE]  -> empty set     -> always contained
  - excluded [0, b]          -> [b+1, MAX]    -> receiver must end at MAX
                                                  and start <= b+1
  - excluded [a, MAX]        -> [0, a-1]      -> receiver must start at 0
                                                  and end+1 >= a
  - otherwise the blanket answer (full domain) is kept.

Usage: fix_char_range.py <path-to-CharRange.java>
"""

import sys


FIND = """        if (range.negated) {
            return start == 0 && end == Character.MAX_VALUE;
        }"""

REPLACE = """        if (range.negated) {
            // range denotes [0, range.start - 1] union [range.end + 1, Character.MAX_VALUE]
            final boolean lowEmpty = range.start == 0;
            final boolean highEmpty = range.end == Character.MAX_VALUE;
            if (lowEmpty && highEmpty) {
                return true; // range denotes the empty set
            }
            if (lowEmpty) {
                return end == Character.MAX_VALUE && start <= range.end + 1;
            }
            if (highEmpty) {
                return start == 0 && end + 1 >= range.start;
            }
            return start == 0 && end == Character.MAX_VALUE;
        }"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_char_range.py <path-to-CharRange.java>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    if REPLACE in src:
        print("fix already present in %s" % path)
        return 0
    if FIND not in src:
        print("expected negated-argument branch not found in %s; aborting" % path, file=sys.stderr)
        return 3
    src = src.replace(FIND, REPLACE, 1)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("patched %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())