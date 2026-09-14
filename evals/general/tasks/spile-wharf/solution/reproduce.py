#!/usr/bin/env python3
"""Reproduction for spile-wharf (reference implementation, equals what a
correct agent submission produces behaviourally).

Every linux kernel prints /proc/meminfo fields as "Name: value kB". Some
fields (e.g. ShadowCallStack, formatted %8lu) lose the space after the
colon once their value reaches 8 digits. psutil.swap_memory() (unfixed)
does `fields = line.split(); mems[fields[0]] = int(fields[1]) * 1024` on
every line, so such a line makes int(b'kB') raise:

    ValueError: invalid literal for int() with base 10: b'kB'

This script builds a synthetic /proc in a scratch directory, points
psutil.PROCFS_PATH at it (the documented public hook), and calls
psutil.swap_memory(). With the bug present it crashes with that ValueError
(exit != 0); once the parser is fixed it prints

    swap total=<total> free=<free> used=<used> percent=<percent>
"""

import os
import tempfile
import warnings

import psutil

MEMINFO = """\
MemTotal:              100 kB
MemFree:               2 kB
SwapTotal:             15 kB
SwapFree:              14 kB
ShadowCallStack:10373888 kB
"""


def main():
    procfs = tempfile.mkdtemp(prefix="psutil-fakeproc-")
    try:
        with open(os.path.join(procfs, "meminfo"), "w") as f:
            f.write(MEMINFO)
        psutil.PROCFS_PATH = procfs
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            mem = psutil.swap_memory()
    finally:
        psutil.PROCFS_PATH = "/proc"
    print(
        "swap total=%d free=%d used=%d percent=%s"
        % (mem.total, mem.free, mem.used, mem.percent)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())