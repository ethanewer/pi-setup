#!/usr/bin/env python3
"""Descriptor keeper for juniper-quill.

Opens /app/archive/lost.csv read-only, then unlinks the path name while keeping
the descriptor open, and sleeps. The only surviving readable reference to the
payload is the open descriptor in this process's fd table, which the agent must
reclaim through /proc/<pid>/fd. Writes its own PID to /tmp/juniper-lockbox.
"""
import os
import time

SRC = "/app/archive/lost.csv"
LOCK = "/tmp/juniper-lockbox"


def main():
    os.makedirs(LOCK, exist_ok=True)
    if not os.path.exists(SRC):
        print("keeper: %s not present at start" % SRC, flush=True)
        time.sleep(600)
        return
    fd = os.open(SRC, os.O_RDONLY)
    try:
        os.unlink(SRC)  # remove the name; fd stays valid
    except OSError as e:
        print("keeper: unlink failed: %r" % e, flush=True)
    with open(os.path.join(LOCK, "keeper.pid"), "w") as f:
        f.write(str(os.getpid()))
    # 5-byte read to prove the fd works, then just hold it open forever.
    os.pread(fd, 5, 0)
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
