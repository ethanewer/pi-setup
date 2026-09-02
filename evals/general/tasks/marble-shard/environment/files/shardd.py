#!/usr/bin/env python3
"""shardd: the Loamware cache-shard keeper.

Opens /app/cache/shard-k7.part read-only, then unlinks the path name while
keeping the descriptor open, and sleeps forever. The payload survives only as
the open file descriptor in this process's fd table (visible under
/proc/<pid>/fd/); nothing records the PID anywhere.
"""
import os
import time

SRC = "/app/cache/shard-k7.part"


def main():
    fd = os.open(SRC, os.O_RDONLY)
    os.unlink(SRC)  # remove the name; the descriptor stays valid
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
