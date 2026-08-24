#!/usr/bin/env python3
"""Simple text-protocol (telnet-style) server on 127.0.0.1:2323.
Sends a banner, reads lines; responds with a secret if a command
is correct, and records every received line (one per line) to /app/server.log.
"""
import socket
import threading

SECRET = "open-sesame-42"
LOG = "/app/server.log"


def handle(conn):
    try:
        conn.sendall(b"BANNER-ELHO-7\r\n")
        # Read until we have at least one complete CRLF/LF-terminated line (or
        # the peer closes), then process each line we received separately.
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        text = data.decode(errors="replace")
        for raw in text.split("\n"):
            line = raw.rstrip("\r").strip("\x00").strip()
            if not line:
                continue
            with open(LOG, "a") as fh:
                fh.write(line + "\n")
            if line == "GIVE-KEY":
                conn.sendall(("KEY=" + SECRET + "\r\n").encode())
            else:
                conn.sendall(b"ERR\r\n")
    except Exception:
        pass
    finally:
        conn.close()


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 2323))
    srv.listen(16)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()