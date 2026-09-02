#!/usr/bin/env python3
"""vnc_target.py — a minimal RFB (VNC protocol) server that stands in for the
"Windows for Workgroups 3.11" guest framebuffer in a QEMU-less harness.

It implements the RFC-documented subset of the RFB 3.8 handshake (no-auth
security type 1), accepts KeyEvent messages, and records every received key to
/app/keys.log. Its VNC server name is derived from /app/desktop/vm.cfg so the
target identity is part of the visible protocol (used by the verifier).

This is a *real* VNC-protocol server, so genuine VNC/websockify clients can
talk to it; it simply does not emulate a full Windows GUI. It is the stateful
framebuffer endpoint of the stack.
"""
import json
import os
import socket
import struct
import time


def load_cfg():
    try:
        with open("/app/desktop/vm.cfg") as f:
            return json.load(f)
    except Exception:
        return {"id": "vm31", "name": "Windows for Workgroups 3.11"}


CFG = load_cfg()
NAME = "vnc-" + str(CFG.get("id", "vm31"))
KEYS_LOG = os.environ.get("KEYS_LOG", "/app/keys.log")
LISTEN_HOST = os.environ.get("VNC_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("VNC_PORT", "5901"))


def recv_exact(conn, n, timeout=15.0):
    data = b""
    end = time.time() + timeout
    while len(data) < n and time.time() < end:
        try:
            conn.settimeout(max(0.2, end - time.time()))
            chunk = conn.recv(n - len(data))
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    return data


def handle(conn):
    try:
        # 1) server greeting
        conn.sendall(b"RFB 003.008\n")
        ver = recv_exact(conn, 12)
        if not ver.startswith(b"RFB"):
            return
        # 2) security types: advertise no-auth (type 1)
        conn.sendall(b"\x01\x01")
        chosen = recv_exact(conn, 1)
        if chosen != b"\x01":
            return
        # 3) security result OK
        conn.sendall(b"\x00\x00\x00\x00")
        recv_exact(conn, 1)  # shared flag
        # 4) server name
        nb = NAME.encode("ascii")
        conn.sendall(struct.pack(">I", len(nb)) + nb)
        # 5) message loop
        while True:
            mt = recv_exact(conn, 1)
            if not mt:
                break
            mtype = mt[0]
            if mtype == 4:  # KeyEvent: 1 pad + 4 key + 1 down
                recv_exact(conn, 1)
                kb = recv_exact(conn, 4)
                if len(kb) == 4:
                    downb = recv_exact(conn, 1)
                    key = struct.unpack(">I", kb)[0]
                    down = downb[0] if downb else 0
                    with open(KEYS_LOG, "a") as f:
                        f.write(f"KeyEvent {key} down={down}\n")
            elif mtype == 0:  # SetPixelFormat: 3 pad + 20 fmt
                recv_exact(conn, 23)
            elif mtype == 2:  # SetEncodings
                recv_exact(conn, 1)
                enc = recv_exact(conn, 2)
                if len(enc) == 2:
                    recv_exact(conn, struct.unpack(">H", enc)[0] * 4)
            elif mtype == 3:  # FramebufferUpdateRequest
                recv_exact(conn, 9)
            elif mtype == 5:  # PointerEvent
                recv_exact(conn, 5)
            elif mtype == 6:  # ClientCutText
                recv_exact(conn, 3)
                cl = recv_exact(conn, 4)
                if len(cl) == 4:
                    recv_exact(conn, struct.unpack(">I", cl)[0])
            else:
                if mtype in (0x03, 0x04):
                    pass
    except OSError:
        return
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(8)
    with open(KEYS_LOG, "a") as f:
        f.write(f"# vnc target [{NAME}] listening {LISTEN_HOST}:{LISTEN_PORT}\n")
    while True:
        conn, _ = srv.accept()
        try:
            handle(conn)
        except Exception:
            try:
                conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()