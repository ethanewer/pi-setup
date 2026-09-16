#!/usr/bin/env python3
"""Deterministic reproduction of the zombie-omission bug in psutil.process_iter().

Contract (see instruction.md):

  * exit 0 and print "FIXED: ..." if the current process appears in
    process_iter()'s output even though its attribute prefetch raises the
    library's zombie-process condition;
  * exit non-zero and print "BUG PRESENT: ..." if the process is silently
    skipped.

The trick that makes the repro deterministic: a real helper process that has
become a zombie is still *yielded* by both the buggy and the fixed iterator
(the attribute prefetch absorbs the zombie condition per attribute), so the
observable difference lives in process_iter()'s handling of a prefetch that
raises the zombie-process condition outright. This script makes exactly that
happen for a known, live process via the standard library's mock, through the
public process_iter() API with an explicit attribute list.
"""
from __future__ import annotations

import os
import sys
import unittest.mock as mock

import psutil


def main() -> int:
    # Populate process_iter()'s internal cache so the current process has a
    # cached Process handle (the exact instance the next iteration will use).
    list(psutil.process_iter())
    proc = psutil._pmap[os.getpid()]

    with mock.patch.object(
        proc, "as_dict", side_effect=psutil.ZombieProcess(proc.pid)
    ):
        pids = [p.pid for p in psutil.process_iter(attrs=["name"])]

    if os.getpid() in pids:
        print(
            f"FIXED: current pid {os.getpid()} is enumerated even though its "
            f"attribute query raises {psutil.ZombieProcess.__name__}"
        )
        return 0
    print(
        f"BUG PRESENT: current pid {os.getpid()} was silently skipped by "
        f"process_iter() although the process is alive and queryable"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())