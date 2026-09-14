#!/usr/bin/env python3
"""Hidden case (no-space swap fields) for spile-wharf.

meminfo where the Swap* fields THEMSELVES are printed without a space
after the colon (magnitudes that actually hit the %8lu width), plus a
9-digit no-space foreign field at the very end (after the swap fields,
proving order independence). Inputs the upstream regression test does not
use: SwapTotal 3000 kB, SwapFree 2000 kB, TokenizerLimit 100000000 kB.

Expected (bytes): total=3072000 free=2048000 used=1024000 percent=33.3
"""

import os
import tempfile
import warnings

import psutil

MEMINFO = """\
MemTotal:             64 kB
MemFree:               1 kB
SwapTotal:3000 kB
SwapFree:2000 kB
TokenizerLimit:100000000 kB
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
    exp = (3072000, 2048000, 1024000, 33.3)
    got = (mem.total, mem.free, mem.used, mem.percent)
    assert got == exp, "expected %r, got %r" % (exp, got)
    assert mem.sin == 0 and mem.sout == 0, (mem.sin, mem.sout)
    print(
        "HIDDEN PASS nospace-swap-fields: total=%d free=%d used=%d percent=%r"
        % got
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())