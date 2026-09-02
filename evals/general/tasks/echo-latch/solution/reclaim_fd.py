#!/usr/bin/env python3
"""Reclaim the content of an unlinked-but-open file descriptor.

Usage: python3 reclaim_fd.py <pidfile> <output_path>
"""
import os
import sys


def main():
    if len(sys.argv) != 3:
        print("usage: reclaim_fd.py <pidfile> <output_path>", file=sys.stderr)
        return 2
    pidfile, out_path = sys.argv[1], sys.argv[2]
    with open(pidfile, "r") as fh:
        pid = int(fh.read().strip())
    fd_dir = "/proc/%d/fd" % pid
    data = None
    for entry in sorted(os.listdir(fd_dir), key=lambda s: (len(s), s)):
        if not entry.isdigit():
            continue
        link = os.path.join(fd_dir, entry)
        try:
            target = os.readlink(link)
        except OSError:
            continue
        if not target.endswith("(deleted)"):
            continue
        try:
            with open(link, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        break
    if data is None:
        print("reclaim_fd: no deleted descriptor found for pid %d" % pid,
              file=sys.stderr)
        return 1
    with open(out_path, "wb") as fh:
        fh.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
