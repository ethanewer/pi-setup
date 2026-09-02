#!/bin/bash
# Oracle for brine-latch: writes the real fd-recovery program to
# /app/reclaim.py, then RUNS it (0-argument form) so /app/recovered.bin is
# produced by doing the actual work against the live relay process.
# Never reads /tests.
set -eu

SOLVER="/app/reclaim.py"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Reclaim the content of an unlinked-but-open file descriptor.

Usage: python3 reclaim.py [PIDFILE] [OUTFILE]
Defaults: PIDFILE=/tmp/brine-vault/relay.pid, OUTFILE=/app/recovered.bin
"""
import os
import sys


def read_pid(pidfile):
    with open(pidfile, "r", encoding="utf-8") as fh:
        return int(fh.read().strip())


def find_deleted_fd(pid):
    """Return the /proc fd number of the (unique) deleted-but-open file."""
    fd_dir = "/proc/%d/fd" % pid
    found = []
    for name in os.listdir(fd_dir):
        if not name.isdigit():
            continue
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.endswith("(deleted)"):
            found.append((int(name), target))
    if not found:
        raise SystemExit("no deleted-but-open descriptor for pid %d" % pid)
    # exactly one deleted file is expected; if several, take the lowest fd
    found.sort()
    return found[0][0]


def main():
    pidfile = sys.argv[1] if len(sys.argv) > 1 else "/tmp/brine-vault/relay.pid"
    outfile = sys.argv[2] if len(sys.argv) > 2 else "/app/recovered.bin"
    pid = read_pid(pidfile)
    fdnum = find_deleted_fd(pid)
    src = "/proc/%d/fd/%d" % (pid, fdnum)
    with open(src, "rb") as fh:
        data = fh.read()
    tmp = outfile + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, outfile)
    print("RECLAIMED %d bytes from pid %d fd %d" % (len(data), pid, fdnum))


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# Run the produced program on the visible appliance (0-argument form).
python3 "$SOLVER"

[ -f /app/recovered.bin ] || { echo "oracle: missing /app/recovered.bin" >&2; exit 1; }
echo "solve.sh done"
sha256sum /app/recovered.bin
