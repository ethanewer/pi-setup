#!/usr/bin/env python3
"""Hidden case (arm64-style) for spile-wharf.

meminfo with spaced swap fields but an 8-digit no-space foreign field
(the arm64 'ShadowCallStack:xxxxxxxx kB' quirk) BEFORE the swap fields.
Inputs the upstream regression test does not use:
  SwapTotal 1024 kB, SwapFree 512 kB, ShadowCallStack 12345678 kB.

Expected (bytes): total=1048576 free=524288 used=524288 percent=50.0
"""

import os
import tempfile
import warnings

import psutil

MEMINFO = """\
MemTotal:           262144 kB
MemFree:            229376 kB
SwapTotal:           1024 kB
SwapFree:             512 kB
ShadowCallStack:12345678 kB
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
    exp = (1048576, 524288, 524288, 50.0)
    got = (mem.total, mem.free, mem.used, mem.percent)
    assert got == exp, "expected %r, got %r" % (exp, got)
    assert mem.sin == 0 and mem.sout == 0, (mem.sin, mem.sout)
    print(
        "HIDDEN PASS arm64-nospace: total=%d free=%d used=%d percent=%r"
        % got
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())