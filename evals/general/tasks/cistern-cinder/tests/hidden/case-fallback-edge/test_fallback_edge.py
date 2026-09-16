# Hidden case for cistern-cinder, layout B: the same parse path fed /proc
# layouts the upstream regression test does not use -- no MemAvailable line at
# all (so available falls back to calculate_avail_vmem() and then to its
# free+cached approximation when /proc/zoneinfo is absent), tabs instead of
# spaces, an unknown no-space field, the exact 9-digit value at which the
# kernel's fixed-width padding finally overflows (ShadowCallStack:100000000),
# and a final line without a trailing newline. Also covers the avail > total
# clamp with a no-space line present.
import os
import tempfile
import warnings

import psutil

FALLBACK_MEMINFO = (
    "MemTotal:\t100 kB\n"
    "MemFree:\t2 kB\n"
    "Buffers:4 kB\n"
    "Cached:5 kB\n"
    "Shmem:\t8 kB\n"
    "Active(file):3 kB\n"
    "Inactive(file):1 kB\n"
    "SReclaimable:2 kB\n"
    "Zombie:99999999 kB\n"
    "ShadowCallStack:100000000 kB"  # no trailing newline
)


def read_vm(content):
    d = tempfile.mkdtemp(prefix="psutil-hidden-fb-")
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


def test_fallback_without_memavailable():
    # No MemAvailable -> estimate; Active(file)/Inactive(file)/SReclaimable
    # are present but /proc/zoneinfo is missing from the scratch procfs, so
    # available falls back to free + cached.
    mem = read_vm(FALLBACK_MEMINFO)
    assert mem.total == 100 * 1024
    assert mem.free == 2 * 1024
    assert mem.available == (2 + 5) * 1024  # free + cached fallback
    assert mem.buffers == 4 * 1024
    assert mem.cached == (5 + 2) * 1024  # + SReclaimable
    assert mem.shared == 8 * 1024
    assert mem.active == 0  # no "Active:" line
    assert mem.inactive == 0
    assert mem.slab == 0
    used = mem.total - mem.available
    assert mem.used == used
    assert mem.percent == 93.0


def test_avail_gt_total_clamped_with_no_space_line():
    # MemAvailable above MemTotal is clamped down to MemFree (container
    # distortion heuristic), with a no-space ShadowCallStack line present.
    content = (
        "MemTotal:   100 kB\n"
        "MemFree:2 kB\n"
        "MemAvailable:999 kB\n"
        "Buffers:4 kB\n"
        "Cached:5 kB\n"
        "Shmem:8 kB\n"
        "ShadowCallStack:0 kB\n"
    )
    mem = read_vm(content)
    assert mem.total == 100 * 1024
    assert mem.free == 2 * 1024
    assert mem.available == 2 * 1024  # clamped to free
    used = mem.total - mem.available
    assert mem.used == used
    assert mem.percent == 98.0