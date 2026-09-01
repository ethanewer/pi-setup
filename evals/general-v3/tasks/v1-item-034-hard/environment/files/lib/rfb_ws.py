#!/usr/bin/env python3
"""rfb_ws.py — a minimal RFB-over-WebSocket client (the "poke-a-key" test path).

It connects to a WebSocket endpoint (either directly at a websockify bridge or
through an nginx reverse proxy), completes the RFB 3.8 no-auth handshake, and
sends a single KeyEvent. This is the client half of the end-to-end keyboard
verification used by the harness and the tests.
"""
import base64
import os
import socket
import struct
import time


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


def ws_connect(host, port, path="/", timeout=8.0):
    sock = socket.create_connection((host, port), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(req.encode("ascii"))
    # Read the response header one byte at a time so we stop exactly at the
    # end of the header (\r\n\r\n). Reading larger chunks here would swallow
    # the first relayed RFB frame that the bridge already queued behind the
    # 101 response, corrupting the protocol exchange.
    sock.settimeout(timeout)
    head = b""
    while b"\r\n\r\n" not in head:
        try:
            d = sock.recv(1)
        except socket.timeout:
            break
        if not d:
            break
        head += d
    first_line = head.split(b"\r\n", 1)[0]
    if b"101" not in first_line:
        sock.close()
        raise RuntimeError("websocket upgrade failed: " + first_line.decode("ascii", "replace"))
    return sock


def ws_recv(sock, timeout=10.0):
    h = recv_exact(sock, 2, timeout)
    if not h:
        return None, b""
    opcode = h[0] & 0x0F
    masked = h[1] & 0x80
    ln = h[1] & 0x7F
    if ln == 126:
        ln = struct.unpack(">H", recv_exact(sock, 2, timeout))[0]
    elif ln == 127:
        ln = struct.unpack(">Q", recv_exact(sock, 8, timeout))[0]
    mask = recv_exact(sock, 4, timeout) if masked else None
    payload = recv_exact(sock, ln, timeout)
    if mask and len(payload) == ln:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def ws_send(sock, payload):
    mask = os.urandom(4)
    ln = len(payload)
    hdr = bytearray([0x81])
    if ln < 126:
        hdr.append(0x80 | ln)
    else:
        hdr.append(0x80 | 126)
        hdr += struct.pack(">H", ln)
    hdr += mask
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes(hdr) + masked)


def rfb_send_key(host, port, key, path="/", timeout=10.0):
    """Open a WebSocket to (host,port,path), run the RFB handshake, and send a
    single KeyEvent for `key`. Returns True if the whole exchange succeeded."""
    sock = ws_connect(host, port, path)
    try:
        # server -> client: version, then security offer [count,type]
        op1, _ver = ws_recv(sock, timeout)
        if op1 not in (1, 2):
            return False
        ws_send(sock, b"RFB 003.008\n")
        op2, sec = ws_recv(sock, timeout)
        if not (sec and sec[0:1] == b"\x01"):
            return False
        ws_send(sock, b"\x01")
        op3, _res = ws_recv(sock, timeout)  # security result
        ws_send(sock, b"\x01")  # shared flag
        op4, _name = ws_recv(sock, timeout)  # server name
        msg = b"\x04\x00" + struct.pack(">I", key) + b"\x00"
        ws_send(sock, msg)
        return True
    finally:
        try:
            sock.close()
        except OSError:
            pass