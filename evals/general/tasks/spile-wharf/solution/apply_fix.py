#!/usr/bin/env python3
"""Apply the minimal upstream fix to psutil's swap_memory() parser.

The buggy parser in psutil/_pslinux.py:

    for line in f:
        fields = line.split()
        mems[fields[0]] = int(fields[1]) * 1024

crashes with ValueError ("invalid literal for int() with base 10: b'kB'")
whenever a /proc/meminfo field is printed without a space after its colon
(e.g. "ShadowCallStack:10373888 kB"). The upstream fix splits each line on
the first ':' and int()s the first whitespace token of the value.

The same three-line snippet also appears in virtual_memory(), so this patch
targets only the block inside swap_memory() (the one followed by the
"swapon/swapoff" comment block and the /proc/meminfo-over-sysinfo comment).
"""

import sys

SRC = "/app/src/psutil/_pslinux.py"

OLD = """            fields = line.split()
            mems[fields[0]] = int(fields[1]) * 1024
"""

NEW = """            # Note: some fields (e.g. "ShadowCallStack:10373888 kB")
            # may not have a space after the colon, see:
            # https://github.com/giampaolo/psutil/issues/2809
            key, value = line.split(b':', 1)
            mems[key + b':'] = int(value.split()[0]) * 1024
"""


def main():
    with open(SRC, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    anchor = "def swap_memory():"
    pos = text.find(anchor)
    if pos < 0:
        print("FATAL: swap_memory() not found in", SRC)
        return 1
    try:
        idx = text.index(OLD, pos)
    except ValueError:
        # Already fixed (or structurally different): only accept if the NEW
        # shape is in place, otherwise fail loudly.
        if NEW in text[pos:]:
            print("swap_memory() already carries the colon-split fix")
            return 0
        print("FATAL: expected buggy parsing block not found after", anchor)
        return 1
    text = text[:idx] + NEW + text[idx + len(OLD):]
    with open(SRC, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("patched swap_memory() in", SRC)
    return 0


if __name__ == "__main__":
    sys.exit(main())