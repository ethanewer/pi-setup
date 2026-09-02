#!/usr/bin/env python3
"""
vine-helix / cleanup worker sweep.

BUGGY (fix me): the stop handler reacts to a stop signal by calling sys.exit().
That skips the in-flight bundle's cleanup, so the required cleanup-complete
marker is never written for an interrupted run.

REQUIRED BEHAVIOR: when the node tells the sweep to stop (SIGTERM/SIGINT):
  1. stop scheduling NEW bundles,
  2. let the still-in-flight bundle run to completion,
  3. run the cleanup handler (append one line,
     "cleanup-complete bundle=<k>", to /app/cleanup/sweep.log),
  4. only then exit(0).

The main while-loop keeps processing until the stop flag is observed set,
so a correct handler must simply set the flag-and-return (never exit) in order
for cleanup to be reached.
"""
import os
import signal
import sys
import time

LOG = "/app/cleanup/sweep.log"


def log(line):
    with open(LOG, "a") as fh:
        fh.write(line + "\n")


STOP = False


def stop(signum, frame):
    global STOP
    STOP = True
    sys.exit(0)  # <-- BUG: exits immediately; the cleanup below never runs


def run_bundle(k):
    deadline = time.monotonic() + 0.35
    while time.monotonic() < deadline:
        _ = k * 7  # busy wait


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    k = 0
    while not STOP:
        run_bundle(k)
        k += 1
        if k > 400:
            break
    # graceful cleanup that MUST run before exit on cancellation
    log("cleanup-complete bundle=%d" % k)


if __name__ == "__main__":
    main()