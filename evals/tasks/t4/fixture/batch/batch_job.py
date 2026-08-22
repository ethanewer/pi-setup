#!/usr/bin/env python3
"""Nightly batch job: appends progress lines to batch.log until finished."""
import os
import random
import time

SEED = os.environ.get("SEED", "0")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LOG = os.path.join(ROOT, "batch.log")
ERROR_LINES = [
    "ERROR: shard 17 timeout talking to cache pool",
    "ERROR: invoice export rejected by downstream (schema v2 mismatch)",
    "ERROR: retry budget exhausted for partition eu-west-3",
]
WARN_LINES = [
    "WARN: retrying flaky upload (attempt 2)",
    "WARN: queue depth above soft limit (depth=142)",
    "WARN: slow checkpoint flush (3.2s)",
    "WARN: retrying flaky upload (attempt 3)",
    "WARN: stale lease on worker-04, renewing",
]


def main():
    r = random.Random(f"{SEED}:t4:batch")
    dur = r.randint(90, 180)
    step = 2.5
    total_chunks = int(dur / step)
    err_at = set(r.sample(range(5, total_chunks - 3), len(ERROR_LINES)))
    warn_at = set(r.sample(sorted(set(range(5, total_chunks - 3)) - err_at), len(WARN_LINES)))
    with open(os.path.join(ROOT, "batch", "batch.pid"), "w") as f:
        f.write(str(os.getpid()))
    with open(LOG, "a", buffering=1) as log:
        log.write("batch: nightly run starting\n")
        start = time.time()
        err_i = warn_i = 0
        for chunk in range(1, total_chunks + 1):
            if chunk in err_at:
                log.write(ERROR_LINES[err_i] + "\n")
                err_i += 1
            elif chunk in warn_at:
                log.write(WARN_LINES[warn_i] + "\n")
                warn_i += 1
            else:
                depth = r.randint(2, 40)
                log.write(f"batch: chunk {chunk}/{total_chunks} processed (queue depth {depth})\n")
            time.sleep(step)
        log.write("BATCH FINISHED rc=0\n")
    print(f"batch job done after {time.time() - start:.0f}s")


if __name__ == "__main__":
    main()
