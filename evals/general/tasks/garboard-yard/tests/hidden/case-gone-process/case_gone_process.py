#!/usr/bin/env python3
"""Regression guard: a process that has genuinely vanished must still be
DROPPED from the enumeration and from the cache.

The correct fix is narrowly aimed at the zombie-process condition: a prefetch
that raises the vanished-process condition (NoSuchProcess) must keep being
removed from the cache and never yielded. A "fix" that swallows every
exception --- or that stops removing entries from the cache altogether ---
passes the zombie tests but violates psutil's contract here, so this case is
exercised on the repaired tree (it must pass; it also passes on the pre-fix
tree, by construction).

Uses the same process_iter(attrs=[...]) path as the zombie cases with a
mock-raised vanished-process condition on a known, live process.
"""
from __future__ import annotations

import os
import sys
import unittest.mock as mock

import psutil


def main() -> int:
    list(psutil.process_iter())  # populate the iterator's cache
    proc = psutil._pmap[os.getpid()]

    with mock.patch.object(
        proc, "as_dict", side_effect=psutil.NoSuchProcess(proc.pid)
    ):
        result = list(psutil.process_iter(attrs=["name"]))

    assert proc.pid not in [p.pid for p in result], (
        "a vanished process was still yielded"
    )
    assert psutil._pmap.get(proc.pid) is None, (
        "a vanished process was not dropped from the cache"
    )
    print("ok: vanished-process semantics preserved "
          "(dropped from enumeration and cache)")
    return 0


if __name__ == "__main__":
    sys.exit(main())