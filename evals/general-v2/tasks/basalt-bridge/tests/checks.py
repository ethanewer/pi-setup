#!/usr/bin/env python3
"""Shared verifier helpers for basalt-bridge (invoked by tests/test.sh and the
hidden-case scripts). Independent of the solution implementation style."""
import os, signal, socket, subprocess, sys, time, urllib.request


def probe_banner(port, timeout=3.0):
    """Connect to the forwarded host port and return the SSH banner or None."""
    try:
        s = socket.socket(); s.settimeout(timeout)
        s.connect(('127.0.0.1', port))
        s.sendall(b'\r\n')
        buf = b''
        end = time.time() + 2.5
        while time.time() < end:
            c = s.recv(256)
            if not c: break
            buf += c
            if b'SSH-2.0-' in buf or len(buf) > 64: break
        s.close()
        text = buf.decode('utf-8', 'replace')
        return text.splitlines()[0] if text.splitlines() else text[:64]
    except Exception:
        return None


def is_elf(path):
    try:
        if not os.access(path, os.X_OK | os.R_OK):
            return False
        with open(path, 'rb') as f:
            return f.read(4) == b'\x7f' + b'ELF'
    except Exception:
        return False


def alive(pid):
    try:
        os.kill(pid, 0); return True
    except Exception:
        return False


def qcow2_ok(path):
    try:
        out = subprocess.run(['qemu-img', 'info', '-U', path],
                             capture_output=True, text=True)
        return out.returncode == 0 and 'qcow2' in out.stdout
    except Exception:
        return False


def http_get(port, path, timeout=5.0):
    try:
        with urllib.request.urlopen(
                'http://127.0.0.1:%d%s' % (port, path), timeout=timeout) as r:
            return r.read()
    except Exception:
        return None


def main(argv):
    cmd = argv[0]
    if cmd == 'banner' and len(argv) >= 2:
        b = probe_banner(int(argv[1]))
        sys.exit(0 if b else 1)
    if cmd == 'elf' and len(argv) >= 2:
        sys.exit(0 if is_elf(argv[1]) else 1)
    if cmd == 'alive' and len(argv) >= 2:
        sys.exit(0 if alive(int(argv[1])) else 1)
    if cmd == 'qcow' and len(argv) >= 2:
        sys.exit(0 if qcow2_ok(argv[1]) else 1)
    if cmd == 'http' and len(argv) >= 3:
        body = http_get(int(argv[1]), argv[2])
        if body is None:
            sys.exit(2)
        sys.stdout.buffer.write(body)
        sys.exit(0)
    if cmd == 'http_ok' and len(argv) >= 4:
        body = http_get(int(argv[1]), argv[2])
        if body is None:
            sys.exit(2)
        try:
            with open(argv[3], 'rb') as f:
                expected = f.read()
        except Exception:
            sys.exit(2)
        sys.exit(0 if body == expected else 1)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))