# Hidden case for cistern-cinder, layout A: several /proc/meminfo fields with
# no space after the colon at once, on the *standard* fields (MemTotal,
# MemFree, HugePages_Total), plus an 8-digit unknown field and a 11-digit
# ShadowCallStack. The upstream regression test only puts the no-space line on
# a single trailing ShadowCallStack field and reads the file through
# mock_open_content; these cases read through psutil.PROCFS_PATH (real file
# reads) with a different field layout and magnitudes, and assert the exact
# computed svmem values including the SReclaimable sum and the percent.
import os
import tempfile
import warnings

import psutil

MEMINFO = """\
MemTotal:100000000 kB
MemFree:2048000 kB
MemAvailable:4096000 kB
Buffers:128 kB
Cached:256 kB
Active:32 kB
Inactive:64 kB
Shmem:8 kB
Slab:16 kB
SReclaimable:24 kB
SwapCached:1 kB
HugePages_Total:0 kB
Hugepagesize:41 kB
DirectMap47M:47 kB
Zombie:99999999 kB
ShadowCallStack:11234567890 kB
"""


def read_vm(content):
    d = tempfile.mkdtemp(prefix="psutil-hidden-multi-")
    with open(os.path.join(d, "meminfo"), "w") as fh:
        fh.write(content)
    old = psutil.PROCFS_PATH
    psutil.PROCFS_PATH = d
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")  # virtual_memory warns on misses
            return psutil.virtual_memory()
    finally:
        psutil.PROCFS_PATH = old


def test_no_space_on_standard_fields():
    mem = read_vm(MEMINFO)
    assert mem.total == 100000000 * 1024
    assert mem.free == 2048000 * 1024
    assert mem.available == 4096000 * 1024
    assert mem.buffers == 128 * 1024
    # cached includes SReclaimable, as "free" does
    assert mem.cached == (256 + 24) * 1024
    assert mem.shared == 8 * 1024
    assert mem.active == 32 * 1024
    assert mem.inactive == 64 * 1024
    assert mem.slab == 16 * 1024
    used = mem.total - mem.available
    assert mem.used == used
    assert mem.percent == 95.9


def test_no_space_on_memfree_only_other_fields_padded():
    # Only MemFree lacks the space; MemTotal/MemAvailable are tab-padded.
    content = (
        "MemTotal:\t100 kB\n"
        "MemFree:7 kB\n"
        "MemAvailable:\t5 kB\n"
        "Buffers:\t2 kB\n"
        "Cached:1 kB\n"
        "Shmem:\t3 kB\n"
        "Slab:4 kB\n"
        "ShadowCallStack:10373888 kB\n"
    )
    mem = read_vm(content)
    assert mem.total == 100 * 1024
    assert mem.free == 7 * 1024
    assert mem.available == 5 * 1024
    assert mem.buffers == 2 * 1024
    assert mem.cached == 1 * 1024
    assert mem.shared == 3 * 1024
    assert mem.slab == 4 * 1024
    used = mem.total - mem.available
    assert mem.used == used
    assert mem.percent == round(used / mem.total * 100, 1)