#!/bin/bash
# velvet-terrace oracle: writes /app/ws_server.py implementing the documented
# WebSocket subset (handshake + frame codec) on top of the sockkit skeleton,
# then self-checks it end-to-end with a raw-socket client on the shipped
# config. Deterministic; never reads /tests.
set -euo pipefail

cat > /app/ws_server.py <<'PYEOF'
"""ws_server.py -- WebSocket server endpoint (documented subset).

Reads /app/config.json (host, port, path) at startup, answers the opening
handshake, then speaks the documented frame codec: masked-echo of text and
binary messages (with fragmentation reassembly), ping -> pong with the same
payload, close-handshake echo, and documented close codes for malformed
frames (1002 protocol error, 1007 invalid UTF-8).

Python standard library only, on top of /app/lib/sockkit.serve.
"""

import base64
import hashlib
import json
import re
import sys

sys.path.insert(0, "/app/lib")
from sockkit import serve  # noqa: E402

MAGIC_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

OP_CONT = 0x0
OP_TEXT = 0x1
OP_BIN = 0x2
OP_CLOSE = 0x8
OP_PING = 0x9
OP_PONG = 0xA

CLOSE_PROTOCOL_ERROR = 1002
CLOSE_INVALID_UTF8 = 1007

KEY_RE = re.compile(r"^[A-Za-z0-9+/]+={0,2}$")


def _key_valid(key):
    """Sec-WebSocket-Key must be well-formed base64 of exactly 16 bytes."""
    if not KEY_RE.fullmatch(key):
        return False
    try:
        return len(base64.b64decode(key, validate=True)) == 16
    except Exception:
        return False

MAX_HEADER_BYTES = 8192
RECV_TIMEOUT = 30.0

CONFIG = {}


class ProtoError(Exception):
    """Raised for any documented protocol violation; carries the close code."""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


def recv_exact(sock, n):
    """Read exactly n bytes (bounded by the socket timeout). None on EOF."""
    buf = bytearray()
    while len(buf) < n:
        try:
            chunk = sock.recv(n - len(buf))
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
    return bytes(buf)


def recv_headers(sock):
    """Read an HTTP request head up to CRLFCRLF; None if too large/EOF."""
    data = bytearray()
    while b"\r\n\r\n" not in data:
        if len(data) > MAX_HEADER_BYTES:
            return None
        try:
            chunk = sock.recv(4096)
        except OSError:
            return None
        if not chunk:
            return None
        data += chunk
    return bytes(data)


def parse_headers(raw):
    """(method, target, version, headers{lower: value}) or None."""
    head = raw.split(b"\r\n\r\n", 1)[0]
    lines = head.split(b"\r\n")
    if not lines:
        return None
    try:
        method, target, version = lines[0].decode("latin-1").split(" ", 2)
    except ValueError:
        return None
    headers = {}
    for line in lines[1:]:
        if b":" not in line:
            return None
        name, _, value = line.partition(b":")
        headers[name.decode("latin-1").strip().lower()] = (
            value.decode("latin-1").strip()
        )
    return method, target, version, headers


def http_400(sock):
    try:
        sock.sendall(
            b"HTTP/1.1 400 Bad Request\r\n"
            b"Connection: close\r\n"
            b"Content-Length: 0\r\n\r\n"
        )
    except OSError:
        pass


def send_frame(sock, opcode, payload):
    """Server->client frame: always unmasked, minimal encoding."""
    b1 = 0x80 | opcode
    n = len(payload)
    if n <= 125:
        head = bytes([b1, n])
    elif n <= 0xFFFF:
        head = bytes([b1, 126]) + n.to_bytes(2, "big")
    else:
        head = bytes([b1, 127]) + n.to_bytes(8, "big")
    try:
        sock.sendall(head + payload)
    except OSError:
        raise ProtoError(0)  # peer gone; unwind quietly


def send_close_raw(sock, payload):
    try:
        send_frame(sock, OP_CLOSE, payload)
    except ProtoError:
        pass


def read_frame(sock):
    """Parse one client frame -> (fin, opcode, payload); None on EOF.

    Raises ProtoError(1002) for every documented protocol violation.
    """
    hdr = recv_exact(sock, 2)
    if hdr is None:
        return None
    b1, b2 = hdr
    fin = bool(b1 & 0x80)
    rsv = b1 & 0x70
    opcode = b1 & 0x0F
    masked = bool(b2 & 0x80)
    length = b2 & 0x7F

    if rsv:
        raise ProtoError(CLOSE_PROTOCOL_ERROR)
    if opcode not in (OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG):
        raise ProtoError(CLOSE_PROTOCOL_ERROR)
    if opcode in (OP_CLOSE, OP_PING, OP_PONG):  # control frames
        if not fin:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)
        if length > 125:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)

    if length == 126:
        ext = recv_exact(sock, 2)
        if ext is None:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)
        length = int.from_bytes(ext, "big")
        if length < 126:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)  # non-minimal encoding
    elif length == 127:
        ext = recv_exact(sock, 8)
        if ext is None:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)
        if ext[0] & 0x80:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)  # length >= 2^63
        length = int.from_bytes(ext, "big")
        if length < 65536:
            raise ProtoError(CLOSE_PROTOCOL_ERROR)  # non-minimal encoding

    if not masked:
        raise ProtoError(CLOSE_PROTOCOL_ERROR)  # client->server MUST mask

    mask_key = recv_exact(sock, 4)
    if mask_key is None:
        raise ProtoError(CLOSE_PROTOCOL_ERROR)
    payload = recv_exact(sock, length)
    if payload is None:
        raise ProtoError(CLOSE_PROTOCOL_ERROR)
    payload = bytes(c ^ mask_key[i % 4] for i, c in enumerate(payload))
    return fin, opcode, payload


def deliver_message(sock, opcode, payload):
    """Validate (text -> UTF-8) and echo a complete message."""
    if opcode == OP_TEXT:
        try:
            payload.decode("utf-8")
        except UnicodeDecodeError:
            send_close_raw(sock, CLOSE_INVALID_UTF8.to_bytes(2, "big"))
            return False
    send_frame(sock, opcode, payload)
    return True


def handle_connection(sock, addr):  # noqa: ARG001 - addr unused
    """Per-connection protocol session (runs in a sockkit thread)."""
    sock.settimeout(RECV_TIMEOUT)
    try:
        raw = recv_headers(sock)
        if raw is None:
            return
        parsed = parse_headers(raw)
        if parsed is None:
            http_400(sock)
            return
        method, target, version, headers = parsed
        path = target.split("?", 1)[0]
        key = headers.get("sec-websocket-key", "")
        upgrade = headers.get("upgrade", "").lower()
        connection = headers.get("connection", "").lower()
        valid = (
            method == "GET"
            and version == "HTTP/1.1"
            and path == CONFIG["path"]
            and upgrade == "websocket"
            and "upgrade" in connection
            and headers.get("sec-websocket-version", "") == "13"
            and key != ""
        )
        if not valid:
            http_400(sock)
            return
        if not _key_valid(key):
            http_400(sock)
            return
        digest = hashlib.sha1((key + MAGIC_GUID).encode("ascii")).digest()
        accept = base64.b64encode(digest).decode("ascii")
        sock.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: " + accept.encode("ascii") + b"\r\n\r\n"
        )

        pending_opcode = None
        pending = b""
        while True:
            try:
                got = read_frame(sock)
            except ProtoError as exc:
                if exc.code:
                    send_close_raw(sock, exc.code.to_bytes(2, "big"))
                return
            if got is None:
                return
            fin, opcode, payload = got

            if opcode == OP_PING:
                send_frame(sock, OP_PONG, payload)
                continue
            if opcode == OP_PONG:
                continue
            if opcode == OP_CLOSE:
                send_close_raw(sock, payload)  # echo code + reason exactly
                return
            if opcode == OP_CONT:
                if pending_opcode is None:
                    send_close_raw(sock, CLOSE_PROTOCOL_ERROR.to_bytes(2, "big"))
                    return
                pending += payload
                if fin:
                    if not deliver_message(sock, pending_opcode, pending):
                        return  # 1007 already sent; stop processing
                    pending_opcode = None
                    pending = b""
                continue
            # text / binary data frame
            if pending_opcode is not None:
                send_close_raw(sock, CLOSE_PROTOCOL_ERROR.to_bytes(2, "big"))
                return
            if fin:
                if not deliver_message(sock, opcode, payload):
                    return  # 1007 already sent; stop processing
            else:
                pending_opcode = opcode
                pending = payload
    except OSError:
        return


def main():
    global CONFIG
    with open("/app/config.json", "r", encoding="utf-8") as fh:
        CONFIG = json.load(fh)
    host = str(CONFIG.get("host", "127.0.0.1"))
    port = int(CONFIG["port"])
    print("ws_server: serving %s:%d path=%s" % (host, port, CONFIG["path"]),
          flush=True)
    serve(host, port, handle_connection)


if __name__ == "__main__":
    main()
PYEOF

# ---- end of deliverable; now self-check it end to end on the shipped config.
python3 - <<'PY'
import base64
import hashlib
import json
import socket
import struct
import subprocess
import sys
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def accept_for(key):
    return base64.b64encode(
        hashlib.sha1((key + GUID).encode("ascii")).digest()
    ).decode("ascii")


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def recv_until(sock, marker):
    data = b""
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            return None
        data += chunk
    return data


def send_masked(sock, opcode, payload, fin=True):
    b1 = (0x80 if fin else 0) | opcode
    n = len(payload)
    if n <= 125:
        b2, ext = 0x80 | n, b""
    elif n <= 0xFFFF:
        b2, ext = 0x80 | 126, struct.pack(">H", n)
    else:
        b2, ext = 0x80 | 127, struct.pack(">Q", n)
    key = b"\x11\x22\x33\x44"
    masked = bytes(c ^ key[i % 4] for i, c in enumerate(payload))
    sock.sendall(bytes([b1, b2]) + ext + key + masked)


def read_server_frame(sock):
    hdr = recv_exact(sock, 2)
    if hdr is None:
        return None
    b1, b2 = hdr
    n = b2 & 0x7F
    if n == 126:
        n = struct.unpack(">H", recv_exact(sock, 2))[0]
    elif n == 127:
        n = struct.unpack(">Q", recv_exact(sock, 8))[0]
    payload = recv_exact(sock, n)
    return b1 & 0x0F, payload


def open_ws(port, path):
    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
    key = base64.b64encode(bytes(range(16))).decode("ascii")
    req = (
        "GET %s HTTP/1.1\r\n"
        "Host: 127.0.0.1:%d\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: %s\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ) % (path, port, key)
    sock.sendall(req.encode("ascii"))
    raw = recv_until(sock, b"\r\n\r\n")
    if raw is None or b" 101 " not in raw.split(b"\r\n", 1)[0]:
        raise AssertionError("handshake not 101: %r" % raw)
    if accept_for(key).encode() not in raw:
        raise AssertionError("accept mismatch")
    return sock


cfg = json.load(open("/app/config.json"))
proc = subprocess.Popen(
    [sys.executable, "/app/ws_server.py"],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
try:
    deadline = time.time() + 15
    while True:
        try:
            probe = socket.create_connection(("127.0.0.1", cfg["port"]), timeout=1)
            probe.close()
            break
        except OSError:
            if time.time() > deadline:
                raise AssertionError("server never listened")
            time.sleep(0.05)

    sock = open_ws(cfg["port"], cfg["path"])
    for op, payload in ((0x1, b"hello wire"), (0x2, b"\x00\x01\xfe\xff"),
                        (0x1, b"")):
        send_masked(sock, op, payload)
        op2, echo = read_server_frame(sock)
        assert (op2, echo) == (op, payload), (op2, echo)
    send_masked(sock, 0x2, b"Z" * 65536)
    op, echo = read_server_frame(sock)
    assert (op, echo) == (0x2, b"Z" * 65536)
    # fragment + interleaved ping
    send_masked(sock, 0x1, b"ab", fin=False)
    send_masked(sock, 0x9, b"mid")
    send_masked(sock, 0x0, b"cd", fin=True)
    op, echo = read_server_frame(sock)
    assert (op, echo) == (0xA, b"mid"), (op, echo)
    op, echo = read_server_frame(sock)
    assert (op, echo) == (0x1, b"abcd"), (op, echo)
    # close echo
    send_masked(sock, 0x8, struct.pack(">H", 1000) + b"done")
    op, echo = read_server_frame(sock)
    assert op == 0x8 and echo == struct.pack(">H", 1000) + b"done", (op, echo)
    assert recv_exact(sock, 1) in (None, b"")
    sock.close()
    print("oracle self-check passed")
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
PY

echo "solve.sh complete -> /app/ws_server.py"