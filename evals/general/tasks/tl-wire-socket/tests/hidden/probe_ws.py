#!/usr/bin/env python3
"""tl-wire-socket hidden probe: raw-socket WebSocket protocol client.

Speaks the documented subset entirely from scratch (socket/struct/hashlib/
base64, stdlib only). For each scenario it opens a fresh connection, sends
the opening handshake with a fresh random key, and recomputes the expected
Sec-WebSocket-Accept from that key (so a canned response always fails). It
exercises:

  - handshake accept recomputation (standard + lowercase header names),
    400 rejections (wrong path, missing key);
  - masked echo round-trips: sizes 0,1,2,125,126,127,255,65535,65536,
    200000 (7-bit / 16-bit / 64-bit length fields) + a seeded random
    payload battery, text and binary;
  - fragmentation: multi-fragment text and binary reassembly into a single
    echo, empty-first-fragment, interleaved ping -> pong between fragments;
  - ping/pong: payload echo, empty ping, ordering vs data frames; pong from
    the client is ignored;
  - close handshake: code+reason echoed exactly, empty close echoed, then
    TCP EOF;
  - malformed frames -> documented close code + TCP close, and nothing
    further is processed after the close.

Deterministic: all generated payloads/masks come from a fixed seed.
Usage: probe_ws.py <config.json>
Exit 0 iff every check passed.
"""

import base64
import hashlib
import json
import random
import socket
import struct
import sys

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

OP_CONT = 0x0
OP_TEXT = 0x1
OP_BIN = 0x2
OP_CLOSE = 0x8
OP_PING = 0x9
OP_PONG = 0xA

SEED = 0xC0FFEE
RNG = random.Random(SEED)

failures = []


def fail(name, why):
    failures.append("%s: %s" % (name, why))


class Conn:
    """A single WebSocket connection under test."""

    def __init__(self, cfg, seed, lowercase=False, path_override=None,
                 key_override=None):
        self.cfg = cfg
        self.sock = socket.create_connection(
            (cfg["host"], cfg["port"]), timeout=15)
        self.sock.settimeout(15)
        self.rng = random.Random(seed)
        if key_override is None:
            key = base64.b64encode(
                bytes(self.rng.randrange(256) for _ in range(16))
            ).decode("ascii")
        else:
            key = key_override
        path = cfg["path"] if path_override is None else path_override
        if lowercase:
            req = (
                "GET %s HTTP/1.1\r\n"
                "host: 127.0.0.1:%d\r\n"
                "upgrade: websocket\r\n"
                "connection: Upgrade\r\n"
                "sec-websocket-key: %s\r\n"
                "sec-websocket-version: 13\r\n\r\n"
            ) % (path, cfg["port"], key)
        else:
            req = (
                "GET %s HTTP/1.1\r\n"
                "Host: 127.0.0.1:%d\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                "Sec-WebSocket-Key: %s\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            ) % (path, cfg["port"], key)
        self.sock.sendall(req.encode("ascii"))
        raw = self.recv_until(b"\r\n\r\n")
        if raw is None:
            self.resp = None
            return
        self.resp = raw
        head = raw.split(b"\r\n\r\n", 1)[0]
        lines = head.split(b"\r\n")
        self.status_line = lines[0].decode("latin-1")
        self.headers = {}
        for line in lines[1:]:
            k, _, v = line.partition(b":")
            self.headers[k.decode("latin-1").strip().lower()] = \
                v.decode("latin-1").strip()
        self.key = key

    # -- raw I/O ---------------------------------------------------------
    def recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            try:
                chunk = self.sock.recv(n - len(buf))
            except OSError:
                return None
            if not chunk:
                return None
            buf += chunk
        return buf

    def recv_until(self, marker, limit=65536):
        data = b""
        while marker not in data:
            if len(data) > limit:
                return None
            try:
                chunk = self.sock.recv(4096)
            except OSError:
                return None
            if not chunk:
                return None
            data += chunk
        return data

    def send_raw(self, b1, b2, ext=b"", mask_key=None, payload=b""):
        head = bytes([b1, b2]) + ext
        if mask_key is not None:
            head += mask_key
            payload = bytes(c ^ mask_key[i % 4] for i, c in enumerate(payload))
        self.sock.sendall(head + payload)

    def send_masked(self, opcode, payload, fin=True, mask_prefix=b""):
        """Send a normal masked frame. mask_prefix lets tests smuggle a
        non-minimal length (ext len bytes encoded in the prefix)."""
        b1 = (0x80 if fin else 0) | (opcode & 0x0F)
        n = len(payload)
        if mask_prefix:
            b2 = 0x80 | mask_prefix[0]
            ext = mask_prefix[1:]
        elif n <= 125:
            b2, ext = 0x80 | n, b""
        elif n <= 0xFFFF:
            b2, ext = 0x80 | 126, struct.pack(">H", n)
        else:
            b2, ext = 0x80 | 127, struct.pack(">Q", n)
        key = bytes(self.rng.randrange(256) for _ in range(4))
        masked = bytes(c ^ key[i % 4] for i, c in enumerate(payload))
        self.sock.sendall(bytes([b1, b2]) + ext + key + masked)

    def read_server_frame(self):
        hdr = self.recv_exact(2)
        if hdr is None:
            return None
        b1, b2 = hdr
        fin = bool(b1 & 0x80)
        opcode = b1 & 0x0F
        if b2 & 0x80:
            raise AssertionError("server frame is masked")
        n = b2 & 0x7F
        if n == 126:
            ext = self.recv_exact(2)
            if ext is None:
                return None
            n = struct.unpack(">H", ext)[0]
        elif n == 127:
            ext = self.recv_exact(8)
            if ext is None:
                return None
            n = struct.unpack(">Q", ext)[0]
        payload = self.recv_exact(n)
        if payload is None:
            return None
        return fin, opcode, payload

    def expect_eof(self):
        """After the server closed, no more bytes may arrive."""
        self.sock.settimeout(1.5)
        try:
            chunk = self.sock.recv(1)
        except socket.timeout:
            return False  # connection still open, waiting silently
        except OSError:
            return True   # reset counts as closed
        return chunk == b""

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def accept_for(key):
    return base64.b64encode(
        hashlib.sha1((key + GUID).encode("ascii")).digest()
    ).decode("ascii")


# ---------------------------------------------------------------------------
# Scenario 1: handshake correctness
# ---------------------------------------------------------------------------
def test_handshake(cfg):
    name = "handshake"
    c = Conn(cfg, seed=1)
    if c.resp is None:
        fail(name, "no response")
    elif " 101 " not in c.status_line:
        fail(name, "status not 101: %r" % c.status_line)
    elif c.headers.get("sec-websocket-accept") != accept_for(c.key):
        fail(name, "accept mismatch: got %r want %r"
             % (c.headers.get("sec-websocket-accept"), accept_for(c.key)))
    c.close()

    c = Conn(cfg, seed=2, lowercase=True)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "lowercase-header handshake rejected")
    elif c.headers.get("sec-websocket-accept") != accept_for(c.key):
        fail(name, "lowercase accept mismatch")
    c.close()

    c = Conn(cfg, seed=3, path_override="/definitely-not-the-path")
    if c.resp is None or " 400 " not in (c.status_line or ""):
        fail(name, "wrong path did not yield 400: %r"
             % (c.status_line if c.resp else None))
    c.close()

    c = Conn(cfg, seed=4, key_override="not-valid-base64!")
    if c.resp is None or " 400 " not in (c.status_line or ""):
        fail(name, "bad key did not yield 400")
    c.close()


# ---------------------------------------------------------------------------
# Scenario 2: masked echo round-trips (one long-lived connection)
# ---------------------------------------------------------------------------
def test_echo_battery(cfg):
    name = "echo-battery"
    c = Conn(cfg, seed=101)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "handshake failed")
        return

    exact_sizes = [0, 1, 2, 125, 126, 127, 255, 65535, 65536, 200000]
    cases = []
    for n in exact_sizes:
        cases.append((OP_TEXT, b"t" * n))
        if n <= 200000:
            cases.append((OP_BIN, bytes((i * 31 + 7) % 256 for i in range(n))))
    text_utf8 = "héllo wörld — 大海 🌊".encode("utf-8")
    cases.append((OP_TEXT, text_utf8))
    # seeded random battery (sizes in both the 16-bit and 64-bit ranges)
    rngb = random.Random(SEED + 1)
    for k in range(12):
        n = rngb.choice([0, 1, 3, 124, 125, 126, 200, rngb.randrange(1000, 40000),
                         rngb.randrange(70000, 120000)])
        if k % 2 == 0:
            payload = bytes(rngb.randrange(32, 127) for _ in range(n))
            cases.append((OP_TEXT, payload))
        else:
            payload = bytes(rngb.randrange(256) for _ in range(n))
            cases.append((OP_BIN, payload))

    passing = True
    for i, (opcode, payload) in enumerate(cases):
        try:
            c.send_masked(opcode, payload)
            got = c.read_server_frame()
        except Exception as exc:  # noqa: BLE001
            fail(name, "case %d raised %r" % (i, exc))
            passing = False
            break
        if got is None:
            fail(name, "case %d (%d bytes) got no response" % (i, len(payload)))
            passing = False
            break
        fin, gop, gpay = got
        if not fin or gop != opcode or gpay != payload:
            fail(name, "case %d (%d bytes, op %d): got fin=%s op=%d len=%d"
                 % (i, len(payload), opcode, fin, gop, len(gpay)))
            passing = False
            break
    c.close()
    if not passing:
        return
    # a canned server would fail earlier; nothing more to assert here


# ---------------------------------------------------------------------------
# Scenario 3: fragmentation reassembly
# ---------------------------------------------------------------------------
def test_fragmentation(cfg):
    name = "fragmentation"
    c = Conn(cfg, seed=201)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "handshake failed")
        c.close()
        return

    # text in 3 fragments, empty middle fragment
    c.send_masked(OP_TEXT, b"first-", fin=False)
    c.send_masked(OP_CONT, b"", fin=False)
    c.send_masked(OP_CONT, b"-last", fin=True)
    got = c.read_server_frame()
    if got is None or got[1] != OP_TEXT or got[2] != b"first--last":
        fail(name, "3-fragment text: got %r" % (got,))
    # bug-check: partial fragments must not have been echoed earlier -- the
    # read above would have consumed them, so ordering already proves it.

    # binary in 3 fragments
    parts = [b"\x00\x01", b"\xfe\xff", b"\x80\x7f"]
    c.send_masked(OP_BIN, parts[0], fin=False)
    c.send_masked(OP_CONT, parts[1], fin=False)
    c.send_masked(OP_CONT, parts[2], fin=True)
    got = c.read_server_frame()
    want = b"".join(parts)
    if got is None or got[1] != OP_BIN or got[2] != want:
        fail(name, "3-fragment binary: got %r" % (got,))

    # fragmentation + interleaved control frames:
    # frag1(text,"ab"), ping("mid"), frag2(cont,"cd")  -> pong first, then echo
    c.send_masked(OP_TEXT, b"ab", fin=False)
    c.send_masked(OP_PING, b"mid")
    c.send_masked(OP_CONT, b"cd", fin=True)
    got = c.read_server_frame()
    if got is None or got[1] != OP_PONG or got[2] != b"mid":
        fail(name, "interleaved ping: got %r" % (got,))
    got = c.read_server_frame()
    if got is None or got[1] != OP_TEXT or got[2] != b"abcd":
        fail(name, "interleave reassembly: got %r" % (got,))

    # client pong must be ignored (next frame is the text echo)
    c.send_masked(OP_PONG, b"ignored")
    c.send_masked(OP_TEXT, b"after-pong")
    got = c.read_server_frame()
    if got is None or got[1] != OP_TEXT or got[2] != b"after-pong":
        fail(name, "pong-not-ignored: got %r" % (got,))
    c.close()


# ---------------------------------------------------------------------------
# Scenario 4: ping/pong
# ---------------------------------------------------------------------------
def test_pingpong(cfg):
    name = "pingpong"
    c = Conn(cfg, seed=301)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "handshake failed")
        c.close()
        return
    c.send_masked(OP_PING, b"hL0")
    got = c.read_server_frame()
    if got is None or got[1] != OP_PONG or got[2] != b"hL0":
        fail(name, "ping payload echo: got %r" % (got,))
    c.send_masked(OP_PING, b"")
    got = c.read_server_frame()
    if got is None or got[1] != OP_PONG or got[2] != b"":
        fail(name, "empty ping: got %r" % (got,))
    # ping then data: order must be pong then echo
    c.send_masked(OP_PING, b"p1")
    c.send_masked(OP_TEXT, b"order")
    got = c.read_server_frame()
    if got is None or got[1] != OP_PONG or got[2] != b"p1":
        fail(name, "ping-before-data order: got %r" % (got,))
    got = c.read_server_frame()
    if got is None or got[1] != OP_TEXT or got[2] != b"order":
        fail(name, "data after ping: got %r" % (got,))
    c.close()


# ---------------------------------------------------------------------------
# Scenario 5: close handshake
# ---------------------------------------------------------------------------
def test_close(cfg):
    name = "close"
    c = Conn(cfg, seed=401)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "handshake failed")
        c.close()
        return
    want = struct.pack(">H", 1000) + b"wind-down"
    c.send_masked(OP_CLOSE, want)
    got = c.read_server_frame()
    if got is None or got[1] != OP_CLOSE or got[2] != want:
        fail(name, "close echo: got %r want %r" % (got, want))
    if not c.expect_eof():
        fail(name, "no EOF after close")
    c.close()

    c = Conn(cfg, seed=402)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "close(empty) handshake failed")
        c.close()
        return
    c.send_masked(OP_CLOSE, b"")
    got = c.read_server_frame()
    if got is None or got[1] != OP_CLOSE or got[2] != b"":
        fail(name, "empty close echo: got %r" % (got,))
    if not c.expect_eof():
        fail(name, "no EOF after empty close")
    c.close()


# ---------------------------------------------------------------------------
# Scenario 6: malformed frames -> documented close codes, then silence
# ---------------------------------------------------------------------------
MALFORMED = [
    # (label, builder(send_fn), expected_close_code)
    ("unmasked-frame", lambda c: c.send_raw(0x81, 0x01, payload=b"x"), 1002),
    ("rsv-bit-set", lambda c: c.send_raw(0xC1, 0x81, mask_key=b"abcd",
                                         payload=b"x"), 1002),
    ("reserved-opcode", lambda c: c.send_masked(0x3, b"x"), 1002),
    ("fragmented-ping", lambda c: c.send_masked(OP_PING, b"x", fin=False), 1002),
    ("control-payload-too-big", lambda c: c.send_masked(
        OP_PING, b"p" * 126), 1002),
    ("nonminimal-16bit", lambda c: c.send_masked(OP_TEXT, b"a" * 100,
                                                 mask_prefix=b"\x7e\x00\x64"),
     1002),
    ("nonminimal-64bit", lambda c: c.send_masked(OP_TEXT, b"b" * 1000,
                                                 mask_prefix=b"\x7f"
                                                 + struct.pack(">Q", 1000)),
     1002),
    ("highbit-64bit", lambda c: c.send_raw(
        0x81, 0x80 | 127, ext=struct.pack(">Q", 0x8000000000000000),
        mask_key=b"abcd", payload=b""), 1002),
    ("bad-utf8-text", lambda c: c.send_masked(OP_TEXT, b"\xff\xfe"), 1007),
    ("cont-without-message", lambda c: c.send_masked(OP_CONT, b"x"), 1002),
    ("data-during-fragment", lambda c: (
        c.send_masked(OP_TEXT, b"abc", fin=False),
        c.send_masked(OP_TEXT, b"def"),
    ), 1002),
]


def test_malformed(cfg):
    name = "malformed"
    for label, builder, code in MALFORMED:
        c = Conn(cfg, seed=500 + code)
        if c.resp is None or " 101 " not in (c.status_line or ""):
            fail(name, "%s: handshake failed" % label)
            c.close()
            continue
        try:
            builder(c)
            got = c.read_server_frame()
        except Exception as exc:  # noqa: BLE001
            fail(name, "%s: raised %r" % (label, exc))
            c.close()
            continue
        if got is None:
            fail(name, "%s: no close frame" % label)
        elif got[1] != OP_CLOSE:
            fail(name, "%s: expected close, got op %d" % (label, got[1]))
        else:
            got_code = struct.unpack(">H", got[2][:2])[0] if len(got[2]) >= 2 \
                else None
            if got_code != code:
                fail(name, "%s: close code %r, want %d" % (label, got_code, code))
        if not c.expect_eof():
            fail(name, "%s: no EOF after close" % label)
        c.close()

    # reassembled text invalid UTF-8: two frames, close 1007 at delivery
    c = Conn(cfg, seed=999)
    if c.resp is None or " 101 " not in (c.status_line or ""):
        fail(name, "reassembled-utf8: handshake failed")
        c.close()
    else:
        c.send_masked(OP_TEXT, b"x\xc3", fin=False)
        c.send_masked(OP_CONT, b"\x28", fin=True)
        got = c.read_server_frame()
        if got is None or got[1] != OP_CLOSE:
            fail(name, "reassembled-utf8: expected close, got %r" % (got,))
        else:
            got_code = struct.unpack(">H", got[2][:2])[0] if len(got[2]) >= 2 \
                else None
            if got_code != 1007:
                fail(name, "reassembled-utf8: code %r want 1007" % (got_code,))
        if not c.expect_eof():
            fail(name, "reassembled-utf8: no EOF after close")
        c.close()


# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) != 2:
        print("usage: probe_ws.py <config.json>", file=sys.stderr)
        return 1
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        cfg = json.load(fh)

    for test in (test_handshake, test_echo_battery, test_fragmentation,
                 test_pingpong, test_close, test_malformed):
        try:
            test(cfg)
        except Exception as exc:  # noqa: BLE001 - never crash the verifier
            fail(test.__name__, "raised unexpected %r" % (exc,))

    if failures:
        print("probe FAIL (%d):" % len(failures))
        for f in failures:
            print("  - %s" % f)
        return 1
    print("probe PASS: config %s:%d path=%s"
          % (cfg["host"], cfg["port"], cfg["path"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())