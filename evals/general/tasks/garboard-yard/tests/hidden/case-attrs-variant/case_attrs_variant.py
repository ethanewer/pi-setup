#!/usr/bin/env python3
"""Hidden case: zombie-condition process with a different attribute set,
an ad_value, an unrelated enumeration in between, and instance identity.

Upstream's regression test uses attrs=["name"] on a fresh cache and checks
PID membership once. This case differs in every other input dimension:

  * attrs=("pid", "create_time") -- a tuple, not a one-element list, and no
    "name" at all;
  * ad_value="?" passed through process_iter() into the prefetch;
  * one unrelated process_iter(attrs=["cpu_times"]) call in between that must
    leave the cache (and hence the mocked handle) intact;
  * asserts the VERY SAME Process instance is yielded (`p in result`), not
    just that the PID appears, and that the identical instance is retained in
    the cache afterwards.

Fails on the pre-fix tree (the instance is dropped, not yielded); passes on
the repaired tree.
"""
from __future__ import annotations

import os
import sys
import unittest.mock as mock

import psutil


def main() -> int:
    list(psutil.process_iter())  # populate the iterator's cache
    proc = psutil._pmap[os.getpid()]

    # An unrelated attribute prefetch must not disturb the cache in either
    # tree; it simply exercises the non-zombie path first.
    list(psutil.process_iter(attrs=["cpu_times"]))

    with mock.patch.object(
        proc, "as_dict", side_effect=psutil.ZombieProcess(proc.pid)
    ):
        result = list(
            psutil.process_iter(attrs=("pid", "create_time"), ad_value="?")
        )

    assert proc in result, (
        "the zombie-condition Process instance was not yielded"
    )
    assert proc.pid in [p.pid for p in result]
    assert psutil._pmap.get(proc.pid) is proc, (
        "the zombie-condition process was dropped from the cache"
    )
    print(f"ok: attrs=('pid','create_time') ad_value='?': instance yielded "
          f"and retained")
    return 0


if __name__ == "__main__":
    sys.exit(main())