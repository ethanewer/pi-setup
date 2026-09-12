#!/usr/bin/env python3
"""Hidden case h3: a three-phase wait with a mixed, changing mask at
interval=0 (poll with no timeout) -- EVENT_READ -> EVENT_WRITE -> EVENT_READ
on one socketpair fd, exercising the unregister/re-register path twice in a
row. The upstream regression test uses at most two events, identical masks,
and intervals > 0; it never touches the interval=0 path with a mask change.

At the unfixed parent the second phase dies with
'KeyError: ... is already registered' (nonzero exit). With the fix every
assertion holds.
"""
import selectors
import socket

from psycopg import waiting

r, w = socket.socketpair()
r.setblocking(False)
w.setblocking(False)
w.sendall(b"x")  # data pending on the read side for phases 1 and 3

seen = []


def gen():
    s = yield selectors.EVENT_READ  # phase 1
    seen.append(s)
    s = yield selectors.EVENT_WRITE  # phase 2: mask change
    seen.append(s)
    s = yield selectors.EVENT_READ  # phase 3: mask change back
    seen.append(s)
    return "DONE"


rv = waiting.wait_selector(gen(), r.fileno(), interval=0.0)
assert rv == "DONE", f"expected DONE, got {rv!r}"
assert seen == [selectors.EVENT_READ, selectors.EVENT_WRITE, selectors.EVENT_READ], \
    f"generator saw {seen}, expected [EVENT_READ, EVENT_WRITE, EVENT_READ]"

# The same fd can be used again afterwards: registration must be clean.
def gen2():
    s = yield selectors.EVENT_WRITE
    return s


rv2 = waiting.wait_selector(gen2(), r.fileno(), interval=0.0)
assert rv2 == selectors.EVENT_WRITE, f"expected EVENT_WRITE, got {rv2!r}"

r.close()
w.close()
print("h3 ok")