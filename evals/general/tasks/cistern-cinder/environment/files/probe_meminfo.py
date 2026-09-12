#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Probe for cistern-cinder.

Feeds psutil.virtual_memory() a crafted /proc/meminfo that contains a field
with no space between its name and its value (the kind arm64 Linux kernels
print for ShadowCallStack once the field exceeds the fixed padding width),
through psutil.PROCFS_PATH, and reports whether the memory statistics are
returned or an exception escapes.

On the buggy tree the parse of such a line raises
  ValueError: invalid literal for int() with base 10: b'kB'
and the probe exits nonzero. A correct fix must return the statistics.
"""

import os
import sys
import tempfile

import psutil

# sanity: we want the installed editable checkout, not a namespace dir
src = os.path.realpath(psutil.__file__)
if not src.startswith("/app/src/"):
    print("WARNING: psutil loaded from %r, expected /app/src/..." % src)

scratch = tempfile.mkdtemp(prefix="psutil-meminfo-probe-")
meminfo = (
    "MemTotal:              100 kB\n"
    "MemFree:               2 kB\n"
    "MemAvailable:          3 kB\n"
    "Buffers:               4 kB\n"
    "Cached:                5 kB\n"
    "Active:                6 kB\n"
    "Inactive:              7 kB\n"
    "Shmem:                 8 kB\n"
    "Slab:                  9 kB\n"
    "ShadowCallStack:10373888 kB\n"
)
with open(os.path.join(scratch, "meminfo"), "w") as fh:
    fh.write(meminfo)

psutil.PROCFS_PATH = scratch
try:
    mem = psutil.virtual_memory()
except Exception as exc:
    print("virtual_memory() raised %s: %s" % (type(exc).__name__, exc))
    sys.exit(1)

print("virtual_memory() total=%d free=%d available=%d percent=%s" % (
    mem.total, mem.free, mem.available, mem.percent))
if mem.total != 100 * 1024:
    print("unexpected total (expected %d)" % (100 * 1024))
    sys.exit(1)
print("OK: a /proc/meminfo layout with a no-space-after-colon field parses cleanly")