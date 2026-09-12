#!/bin/bash
# cistern-forge oracle: apply the genuine upstream one-function fix to
# waiting.wait_selector -- track the last registration mask and only
# unregister+re-register the fd when the generator's new wait state differs
# from the current one -- then prove the two-phase repro flips from a
# KeyError to 'returned: COMPLETED'.
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p = Path("/app/src/psycopg/psycopg/waiting.py")
s = p.read_text()

old = (
    "            sel.register(fileno, s)\n"
    "            while True:\n"
    "                if not (rlist := sel.select(timeout=interval)):\n"
    "                    # Check if it was a timeout or we were disconnected\n"
    "                    _check_fd_closed(fileno)\n"
    "                    gen.send(READY_NONE)\n"
    "                    continue\n"
    "\n"
    "                ready = rlist[0][1]\n"
    "                s = gen.send(ready)\n"
    "                sel.register(fileno, s)\n"
)
new = (
    "            sel.register(fileno, (last_s := s))\n"
    "            while True:\n"
    "                if not (rlist := sel.select(timeout=interval)):\n"
    "                    # Check if it was a timeout or we were disconnected\n"
    "                    _check_fd_closed(fileno)\n"
    "                    gen.send(READY_NONE)\n"
    "                    continue\n"
    "\n"
    "                ready = rlist[0][1]\n"
    "                s = gen.send(ready)\n"
    "                if last_s != s:\n"
    "                    sel.unregister(fileno)\n"
    "                    sel.register(fileno, (last_s := s))\n"
)
n = s.count(old)
assert n == 1, f"anchor for the fix found {n} times, expected exactly 1"
p.write_text(s.replace(old, new, 1))
print("patched wait_selector to only re-register the fd when the wait state changes")
PY
out=$(python3 - <<'EOF'
import socket, selectors
from psycopg import waiting
r, w = socket.socketpair()
def gen():
    yield selectors.EVENT_WRITE   # phase 1: wait until writable
    yield selectors.EVENT_READ    # phase 2: wait for read after wake-up
    return "COMPLETED"
try:
    rv = waiting.wait_selector(gen(), r.fileno(), interval=0.05)
    print("returned:", rv)
except Exception as ex:
    print(type(ex).__name__, "-", ex)
EOF
)
[ "$out" = "returned: COMPLETED" ] || { echo "oracle repro printed '$out', expected 'returned: COMPLETED'" >&2; exit 1; }
echo "repro now returns: COMPLETED"