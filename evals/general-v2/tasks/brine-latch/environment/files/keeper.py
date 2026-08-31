#!/usr/bin/env python3
"""ColdBrine relay daemon (visible appliance instance).

Opens the snapshot and a live calibration table, unlinks the snapshot's
pathname while holding the descriptor open, records its PID, and sleeps. The
snapshot's bytes survive only via this process's open fd.
"""
import os
import time

SNAPSHOT = "/app/vault/payload.bin"
DECOY = "/app/vault/decoy.txt"
LOCK = "/tmp/brine-vault"


def main():
    os.makedirs(LOCK, exist_ok=True)
    fd = os.open(SNAPSHOT, os.O_RDONLY)
    decoy_fd = os.open(DECOY, os.O_RDONLY)
    os.unlink(SNAPSHOT)  # rotate: name is gone, fd stays valid
    with open(os.path.join(LOCK, "relay.pid"), "w") as f:
        f.write(str(os.getpid()))
    os.pread(fd, 4, 0)  # prove the fd is live
    while True:
        time.sleep(600)


if __name__ == "__main__":
    main()
