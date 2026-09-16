#!/usr/bin/env python3
"""Hidden case h1: two-phase wait on ONE file descriptor with a CHANGING wait
mask -- exactly the connect-style flow that crashes the unfixed upstream code
(a generator that first waits for EVENT_WRITE and, once woken, waits for
EVENT_READ on the same socket). The upstream regression test never changes the
wait mask inside a single wait call: its generator yields the same event every
time. On a socketpair both phases are immediately ready, exercised at
interval=0.01, and the generator records which ready mask it was sent each
time.

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
w.sendall(b"x")  # make the read side ready for phase 2

seen = []


def gen():
    s = yield selectors.EVENT_WRITE  # phase 1: wait until writable
    seen.append(s)
    s = yield selectors.EVENT_READ  # phase 2: wait for read after wake-up
    seen.append(s)
    return "COMPLETED"


rv = waiting.wait_selector(gen(), r.fileno(), interval=0.01)
assert rv == "COMPLETED", f"expected COMPLETED, got {rv!r}"
assert seen == [selectors.EVENT_WRITE, selectors.EVENT_READ], \
    f"generator saw {seen}, expected [EVENT_WRITE, EVENT_READ]"

# The wait call must leave the fd in a clean state: a fresh single-phase wait
# on the same fd must work and must not re-register a dangling descriptor.
def gen2():
    s = yield selectors.EVENT_READ
    return s


rv2 = waiting.wait_selector(gen2(), r.fileno(), interval=0.01)
assert rv2 == selectors.EVENT_READ, f"expected EVENT_READ, got {rv2!r}"

r.close()
w.close()
print("h1 ok")