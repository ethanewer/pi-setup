"""sockkit: a tiny blocking TCP server skeleton with a per-connection
callback API.

The only public entry point is `serve(host, port, handler)`. It binds the
listener, then for every accepted connection spawns a daemon thread that
calls `handler(sock, addr)`. When the handler returns (or raises), the
socket is closed. One misbehaving connection can never kill the listener.

Written from scratch for the velvet-terrace bench; not a copy of any
project. Python stdlib only.
"""

import socket
import threading


def _dispatch(sock, addr, handler):
    try:
        handler(sock, addr)
    except Exception as exc:  # noqa: BLE001 - keep the listener alive
        print("sockkit handler error for %r: %s" % (addr, exc), flush=True)
    finally:
        try:
            sock.close()
        except OSError:
            pass


def serve(host, port, handler, backlog=16):
    """Bind (host, port) and serve forever.

    handler(sock, addr) runs in a fresh thread per connection. The socket
    passed to the handler is the raw connected socket; the handler owns it
    and it is closed once the handler returns. This call blocks the calling
    thread and only returns if the listener fails.
    """
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((host, port))
    listener.listen(backlog)
    print("sockkit listening on %s:%d" % (host, port), flush=True)
    while True:
        try:
            conn, addr = listener.accept()
        except OSError:
            break
        thread = threading.Thread(
            target=_dispatch, args=(conn, addr, handler), daemon=True
        )
        thread.start()