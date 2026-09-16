#!/usr/bin/env python3
"""Hidden case h2: the real connect flow over actual TCP -- a non-blocking
client socket that first waits for EVENT_WRITE (connect handshake completing)
and, once woken, waits for EVENT_READ (the server greeting). This is the exact
user-visible symptom: a multi-phase operation on one connection socket. The
upstream regression test only ever listens on a server socket and connects
from a separate writer; it never runs the two-phase wait on the connecting
side.

At the unfixed parent the second phase dies with
'KeyError: ... is already registered' (nonzero exit). With the fix every
assertion holds.
"""
import selectors
import socket
import threading

from psycopg import waiting

srv = socket.socket()
srv.bind(("127.0.0.1", 0))
srv.listen(1)
port = srv.getsockname()[1]


def server():
    c, _ = srv.accept()
    c.sendall(b"hello")
    c.close()


t = threading.Thread(target=server)
t.start()

cli = socket.socket()
cli.setblocking(False)
try:
    cli.connect(("127.0.0.1", port))
except BlockingIOError:
    pass  # still connecting: exactly what phase 1 waits for

seen = []


def gen():
    s = yield selectors.EVENT_WRITE  # connect completing
    seen.append(s)
    s = yield selectors.EVENT_READ  # server greeting arriving
    seen.append(s)
    return "CONNECTED"


rv = waiting.wait_selector(gen(), cli.fileno(), interval=0.02)
assert rv == "CONNECTED", f"expected CONNECTED, got {rv!r}"
assert seen == [selectors.EVENT_WRITE, selectors.EVENT_READ], \
    f"generator saw {seen}, expected [EVENT_WRITE, EVENT_READ]"

t.join(timeout=5)
assert not t.is_alive(), "server thread did not finish"
cli.close()
srv.close()
print("h2 ok")