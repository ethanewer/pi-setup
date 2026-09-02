#!/bin/bash
# Real oracle for marble-shard: write the reusable /proc-scanning recovery
# program, then RUN it on the live appliance for shard k7 to produce
# /app/recovered.txt. Never reads /tests.
set -eu

RECOVER="/app/recover.py"

cat > "$RECOVER" <<'PY'
#!/usr/bin/env python3
"""Reclaim the content of a deleted-but-open cache shard from /proc.

Usage: python3 recover.py <shard_id> <output_path>
Exit 0 on success, 2 when no matching deleted payload exists.
"""
import os
import sys


def deleted_fd_targets():
    """Yield (pid, fd, /proc path) for links pointing at deleted files."""
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fddir = "/proc/%s/fd" % pid
        try:
            entries = os.listdir(fddir)
        except OSError:
            continue
        for fd in entries:
            path = os.path.join(fddir, fd)
            try:
                target = os.readlink(path)
            except OSError:
                continue
            if target.endswith("(deleted)"):
                yield pid, fd, path


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: recover.py <shard_id> <output_path>\n")
        sys.exit(1)
    shard_id, out_path = sys.argv[1], sys.argv[2]
    marker = "SHARD_ID=%s" % shard_id

    for pid, fd, path in deleted_fd_targets():
        try:
            st = os.stat(path)
            import stat as statmod
            if not statmod.S_ISREG(st.st_mode) or st.st_size == 0 or st.st_size > 32 * 1024 * 1024:
                continue
            with open(path, "rb") as fh:
                first = fh.readline()
                if first.rstrip(b"\r\n") != marker.encode():
                    continue
                fh.seek(0)
                payload = fh.read()
        except OSError:
            continue
        with open(out_path, "wb") as out:
            out.write(payload)
        sys.exit(0)

    sys.exit(2)


if __name__ == "__main__":
    main()
PY

chmod +x "$RECOVER"

python3 "$RECOVER" k7 /app/recovered.txt

echo "solve.sh done -> $RECOVER and /app/recovered.txt"
head -3 /app/recovered.txt
