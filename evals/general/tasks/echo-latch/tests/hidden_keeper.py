#!/usr/bin/env python3
"""Fresh keeper used by the verifier for hidden cases.

Usage: python3 hidden_keeper.py <pidfile> <payload_path> <decoy_path> [...]

Opens the payload read-only, unlinks its path, opens every decoy (which stay
linked), writes its PID to <pidfile>, then sleeps. Exactly one deleted
descriptor ever exists.
"""
import os
import sys
import time


def main():
    pidfile, payload = sys.argv[1], sys.argv[2]
    decoys = sys.argv[3:]
    for d in decoys:
        try:
            os.open(d, os.O_RDONLY)
        except OSError:
            pass
    fd = os.open(payload, os.O_RDONLY)
    os.unlink(payload)
    os.makedirs(os.path.dirname(os.path.abspath(pidfile)), exist_ok=True)
    with open(pidfile, "w") as f:
        f.write(str(os.getpid()))
    os.pread(fd, 5, 0)
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
