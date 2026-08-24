#!/usr/bin/env python3
"""ws_bridge.py — a minimal websockify-style WebSocket->RFB bridge.

It accepts WebSocket upgrades on a listen socket (default 127.0.0.1:8080,
path /ws) and for each client opens a TCP connection to an RFB/VNC target
(default 127.0.0.1:5901), then relays bytes in BOTH directions:

  client --(WebSocket)--> ws_bridge --(TCP)--> vnc target
  client <--(WebSocket)-- ws_bridge <--(TCP)-- vnc target

This is the "websockify" hop that lets a browser/noVNC client talk to a raw
RFB framebuffer. Client->server frames are masked and unmasked here; server->
client frames are emitted unmasked (RFC 6455).

CLI:  python3 lib/ws_bridge.py --host H --port P --path /ws --target H:PORT

Env overrides: WS_LISTEN_HOST, WS_LISTEN_PORT, WS_PATH, WS_TARGET.
"""
import argparse
import base64
import hashlib
import os
import socket
import struct
import threading
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
LISTEN_HOST = os.environ.get("WS_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("WS_LISTEN_PORT", "8080"))
WS_PATH = os.environ.get("WS_PATH", "/ws")


def recv_exact(sock, n, timeout=10.0):
    data = b""
    end = time.time() + timeout
    while len(data) < n and time.time() < end:
        try:
            sock.settimeout(max(0.2, end - time.time()))
            chunk = sock.recv(n - len(data))
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    return data


def _b64_accept(key_bytes):
    key = key_bytes.decode("ascii", "replace").strip()
    return base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest()).decode("ascii")


def _read_http_head(sock, maxlen=8192):
    data = b""
    while b"\r\n\r\n" not in data and len(data) < maxlen:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    return data


class Session:
    """One websocket client bridged to one TCP RFB target."""

    def __init__(self, wssock, target_addr):
        self.ws = wssock
        self.tcp = socket.create_connection(target_addr, timeout=10.0)
        self.tcp.settimeout(0.2)

    # -------- read one client frame -> payload (masked unmasked) --------
    def recv_payload(self):
        h = recv_exact(self.ws, 2)
        if not h or len(h) < 2:
            return None
        mask = bool(h[1] & 0x80)
        ln = h[1] & 0x7F
        if ln == 126:
            e = recv_exact(self.ws, 2)
            if len(e) < 2:
                return None
            ln = struct.unpack(">H", e)[0]
        elif ln == 127:
            e = recv_exact(self.ws, 8)
            if len(e) < 8:
                return None
            ln = struct.unpack(">Q", e)[0]
        k = recv_exact(self.ws, 4) if mask else None
        p = recv_exact(self.ws, ln)
        if k and len(p) == ln:
            p = bytes(b ^ k[i % 4] for i, b in enumerate(p))
        return p

    def client_to_target(self):
        while True:
            data = self.recv_payload()
            if data is None:
                break
            try:
                self.tcp.sendall(data)
            except OSError:
                break
        try:
            self.tcp.close()
        except OSError:
            pass

    def target_to_client(self):
        while True:
            try:
                chunk = self.tcp.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            # build a single unmasked websocket frame per chunk
            out = bytearray([0x02])
            ln = len(chunk)
            if ln < 126:
                out.append(ln)
            elif ln < 65536:
                out.append(126)
                out += struct.pack(">H", ln)
            else:
                out.append(127)
                out += struct.pack(">Q", ln)
            out += chunk
            try:
                self.ws.sendall(bytes(out))
            except OSError:
                break
        try:
            self.tcp.close()
            self.ws.close()
        except OSError:
            pass


def handle(conn, target_addr):
    try:
        head = _read_http_head(conn)
        if b"websocket" not in head.lower():
            conn.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            return
        key = None
        for line in head.split(b"\r\n"):
            if line.lower().startswith(b"sec-websocket-key:"):
                key = line.split(b":", 1)[1]
                break
        if not key:
            conn.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            return
        accept = _b64_accept(key)
        resp = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode("ascii")
        conn.sendall(resp)
        s = Session(conn, target_addr)
        t = threading.Thread(target=s.target_to_client, daemon=True)
        t.start()
        s.client_to_target()
        t.join(timeout=2)
    except OSError:
        pass
    except Exception:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default=LISTEN_HOST)
    ap.add_argument("--port", type=int, default=LISTEN_PORT)
    ap.add_argument("--path", default=WS_PATH)
    ap.add_argument("--target", default=os.environ.get("WS_TARGET", "127.0.0.1:5901"))
    a = ap.parse_args()
    host, port = a.host, a.port
    th, tp = a.target.split(":")
    target_addr = (th, int(tp))
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(64)
    with open("/tmp/ws_bridge_ready", "w") as f:
        f.write(f"{host}:{port} -> {a.target}\n")
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn, target_addr), daemon=True).start()


if __name__ == "__main__":
    main()