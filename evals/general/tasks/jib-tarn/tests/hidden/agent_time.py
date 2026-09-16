"""Timing driver for the agent's sundial repository (hidden-case size check).

Runs the agent's hot-path implementation at a hidden input size, validates
that the result shape is sane, and prints one JSON line with the minimum
wall time (ms) over ``repeats`` runs.  Fresh random data is generated
before every timed run (generation is outside the timed window), so a
solution that memoizes on input content or on (n, k) cannot buy cache hits
in the timed runs; the seed scheme matches tests/ref/ref_window.py.
"""

import gc
import json
import random
import sys
import time

sys.path.insert(0, "/app/repo/src")

from sundial.window import slide  # noqa: E402


def main() -> int:
    seed, n, k = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    repeats = int(sys.argv[4]) if len(sys.argv) > 4 else 2
    rng = random.Random(
        (seed * 0x100000001B3 + n * 0x9E3779B97F4A7C15 + k * 0xC6A4A7935BD1E995)
        % 0xFFFFFFFFFFFFFFFF
    )
    data = [rng.randrange(0, 1 << 20) for _ in range(n)]
    out = slide(data, k)
    if len(out) != n - k + 1:
        print(json.dumps({"ms": -1.0, "ok": False, "err": "length mismatch"}))
        return 1
    if out and out[0] != max(data[:k]):
        print(json.dumps({"ms": -1.0, "ok": False, "err": "window max mismatch"}))
        return 1
    gc.collect()
    gc.disable()
    try:
        best = None
        for _ in range(repeats):
            # Fresh dataset per timed run: content-keyed or (n, k)-keyed
            # memoization therefore pays the full per-window cost, and the
            # result is validated against the fresh dataset after the timer,
            # so a stale cached answer cannot satisfy the driver.
            data = [rng.randrange(0, 1 << 20) for _ in range(n)]
            t0 = time.perf_counter()
            out = slide(data, k)
            elapsed = time.perf_counter() - t0
            try:
                ok_shape = len(out) == n - k + 1
                ok_head = (not out) or out[0] == max(data[:k])
                ok_tail = (not out) or out[-1] == max(data[-k:])
            except Exception:
                ok_shape = ok_head = ok_tail = False
            if not (ok_shape and ok_head and ok_tail):
                print(json.dumps({"ms": -1.0, "ok": False,
                                  "err": "wrong result for fresh input"}))
                return 1
            if best is None or elapsed < best:
                best = elapsed
    finally:
        gc.enable()
    print(json.dumps({"ms": best * 1000.0, "ok": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())