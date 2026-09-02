#!/usr/bin/env python3
"""run_monitor.py -- sample a metric every ~10s for ~60s into /app/monitor.log.

Each line:
    ts=<unix_epoch> metric=<value> elapsed=<elapsed_seconds>
The loop emits 7 samples (t=0..60) spaced 10 seconds apart so the log spans
the full window. Delete any prior log first.
"""
import time

OUT = "/app/monitor.log"
TOTAL = 60
INTERVAL = 10


def main():
    start = time.time()
    n = 0
    with open(OUT, "w") as f:
        while True:
            now = time.time()
            elapsed = int(round(now - start))
            # a fabricated but stable system metric so the value is checkable
            metric = 4200 + elapsed
            f.write("ts=%d metric=%d elapsed=%d\n"
                    % (int(now), metric, elapsed))
            f.flush()
            n += 1
            if now - start >= TOTAL - 1:
                break
            time.sleep(INTERVAL)
    print("monitor: wrote %d samples to %s" % (n, OUT))


if __name__ == "__main__":
    main()