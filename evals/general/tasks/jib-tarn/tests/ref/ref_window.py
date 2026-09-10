"""Reference implementation of sundial's hot path, with a timing driver.

The verifier compares the agent's repository against this linear-time
implementation on the three hidden input sizes.  The driver prints one JSON
line with the minimum wall time (ms) over ``repeats`` runs and a sanity check
of the result shape.

This file is part of the test image; agents never see /tests.
"""

import gc
import json
import random
import sys
import time
from collections import deque
from typing import List, Sequence


def slide(data: Sequence[int], size: int) -> List[int]:
    """Linear-time sliding-window maximum (monotonic deque)."""
    k = max(1, size)
    n = len(data)
    if n == 0 or k > n:
        return []
    out = [0] * (n - k + 1)
    dq: deque = deque()
    dq_append = dq.append
    dq_pop = dq.pop
    dq_popleft = dq.popleft
    data_get = data.__getitem__
    idx = 0
    for j, x in enumerate(data):
        while dq and data_get(dq[-1]) <= x:
            dq_pop()
        dq_append(j)
        if dq[0] <= j - k:
            dq_popleft()
        if j >= k - 1:
            out[idx] = data_get(dq[0])
            idx += 1
    return out


def main() -> int:
    seed, n, k = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    repeats = int(sys.argv[4]) if len(sys.argv) > 4 else 2
    rng = random.Random(
        (seed * 0x100000001B3 + n * 0x9E3779B97F4A7C15 + k * 0xC6A4A7935BD1E995)
        % 0xFFFFFFFFFFFFFFFF
    )
    data = [rng.randrange(0, 1 << 20) for _ in range(n)]
    out = slide(data, k)
    if len(out) != n - k + 1 or (out and out[0] != max(data[:k])):
        print(json.dumps({"ms": -1.0, "ok": False, "err": "reference check failed"}))
        return 1
    gc.collect()
    gc.disable()
    try:
        best = None
        for _ in range(repeats):
            # Fresh dataset per timed run, mirroring tests/hidden/agent_time.py
            # so both drivers time the same workload distribution and neither
            # can be short-circuited by memoization.
            data = [rng.randrange(0, 1 << 20) for _ in range(n)]
            t0 = time.perf_counter()
            slide(data, k)
            elapsed = time.perf_counter() - t0
            if best is None or elapsed < best:
                best = elapsed
    finally:
        gc.enable()
    print(json.dumps({"ms": best * 1000.0, "ok": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())