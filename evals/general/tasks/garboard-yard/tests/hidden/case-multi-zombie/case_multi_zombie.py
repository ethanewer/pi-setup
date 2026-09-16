#!/usr/bin/env python3
"""Hidden case: several simultaneous zombie-condition processes.

Upstream's regression test mocks a single process (the test runner's own) with
attrs=["name"] and checks PID membership. This case exercises the same
process_iter() code path from inputs it does not use:

  * three zombie-condition processes at once (the current process plus two
    long-lived helper children),
  * a two-attribute prefetch list ["name", "status"],
  * all three PIDs present in the output,
  * output sorted by PID (process_iter()'s documented ordering), and
  * the internal cache retains the SAME Process instances afterwards (the
    buggy code removes them, so the omission repeats on every call).

Fails (non-zero, AssertionError) on the pre-fix tree; passes on the fixed
tree.
"""
from __future__ import annotations

import os
import subprocess
import sys
import unittest.mock as mock

import psutil


def main() -> int:
    helpers = [subprocess.Popen(["sleep", "120"]) for _ in range(2)]
    try:
        list(psutil.process_iter())  # populate the iterator's cache
        targets = [psutil._pmap[os.getpid()]]
        targets += [psutil._pmap[h.pid] for h in helpers]
        assert all(t is not None for t in targets), "helper pids were not cached"

        with mock.patch.object(
            targets[0], "as_dict", side_effect=psutil.ZombieProcess(targets[0].pid)
        ), mock.patch.object(
            targets[1], "as_dict", side_effect=psutil.ZombieProcess(targets[1].pid)
        ), mock.patch.object(
            targets[2], "as_dict", side_effect=psutil.ZombieProcess(targets[2].pid)
        ):
            result = list(psutil.process_iter(attrs=["name", "status"]))

        pids = [p.pid for p in result]
        expect = sorted(t.pid for t in targets)
        for pid in expect:
            assert pid in pids, f"pid {pid} missing from the enumeration"
        assert pids == sorted(pids), "enumeration is not pid-sorted"
        for t in targets:
            assert psutil._pmap.get(t.pid) is t, (
                f"pid {t.pid} was dropped from process_iter()'s cache"
            )
        print(f"ok: {len(expect)} zombie-condition processes enumerated, "
              f"sorted, cache retained")
        return 0
    finally:
        for h in helpers:
            h.terminate()


if __name__ == "__main__":
    sys.exit(main())