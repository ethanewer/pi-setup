#!/usr/bin/env python3
"""Hidden case (mixed spacing) for spile-wharf.

meminfo with mostly spaced lines, an 8-digit no-space foreign field in the
MIDDLE (between the Swap fields), and a different no-space field at the
end. Inputs the upstream regression test does not use:
SwapTotal 1000 kB, SwapFree 250 kB, PlusSs 88888888 kB, MemCommit:3 kB.

Expected (bytes): total=1024000 free=256000 used=768000 percent=75.0
"""

import os
import tempfile
import warnings

import psutil

MEMINFO = """\
MemTotal:              100 kB
MemFree:                50 kB
SwapTotal:             1000 kB
PlusSs:88888888 kB
SwapFree:              250 kB
MemCommit:3 kB
"""


def main():
    procfs = tempfile.mkdtemp(prefix="psutil-hcase-")
    try:
        with open(os.path.join(procfs, "meminfo"), "w") as f:
            f.write(MEMINFO)
        psutil.PROCFS_PATH = procfs
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            mem = psutil.swap_memory()
    finally:
        psutil.PROCFS_PATH = "/proc"
    exp = (1024000, 256000, 768000, 75.0)
    got = (mem.total, mem.free, mem.used, mem.percent)
    assert got == exp, "expected %r, got %r" % (exp, got)
    assert mem.sin == 0 and mem.sout == 0, (mem.sin, mem.sout)
    print(
        "HIDDEN PASS mixed-spacing: total=%d free=%d used=%d percent=%r" % got
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())