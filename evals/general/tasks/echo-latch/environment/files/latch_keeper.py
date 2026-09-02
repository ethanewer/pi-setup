#!/usr/bin/env python3
"""Descriptor keeper for the Vellum Press render node.

Opens /app/spool/frame_buffer.bin read-only, then unlinks the path while the
descriptor stays open, and sleeps forever. Also holds open a still-linked decoy
(/app/spool/manifest.txt). The only readable reference to the payload is the
open descriptor in this process's fd table. Writes its PID to
/app/spool/.latch.pid.
"""
import os
import time

SPOOL = "/app/spool"
SRC = os.path.join(SPOOL, "frame_buffer.bin")
DECOY = os.path.join(SPOOL, "manifest.txt")
PIDFILE = os.path.join(SPOOL, ".latch.pid")


def main():
    os.makedirs(SPOOL, exist_ok=True)
    if os.path.exists(DECOY):
        decoy_fd = os.open(DECOY, os.O_RDONLY)  # still-linked decoy
    else:
        decoy_fd = -1
    if not os.path.exists(SRC):
        print("keeper: %s not present at start" % SRC, flush=True)
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
        time.sleep(600)
        return
    fd = os.open(SRC, os.O_RDONLY)
    try:
        os.unlink(SRC)  # the name disappears; the inode lives on via fd
    except OSError as exc:
        print("keeper: unlink failed: %r" % exc, flush=True)
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    os.pread(fd, 5, 0)  # prove the descriptor works
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
