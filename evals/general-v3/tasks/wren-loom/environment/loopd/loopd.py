#!/usr/bin/env python3
"""loopd -- the Foundry Commons mailing-list daemon.

Reads its configuration ONLY from the canonical path /etc/loopd/lists.conf at
startup and re-reads it on SIGHUP. Serves a line-based control protocol on
127.0.0.1:7871. Config placed anywhere else is ignored by design.
"""
import os
import signal
import socket

CONFIG_PATH = "/etc/loopd/lists.conf"
PORT = 7871
PIDFILE = "/run/loopd.pid"

STATE = {"lists": {}}


def load_config(path=CONFIG_PATH):
    """Parse the canonical config. Semantics:
    - blank lines and lines starting with '#' are ignored;
    - '[name]' starts (re)definition of list `name` (last definition wins);
    - 'key = value' sets address / members (comma-separated) / enabled
      (exactly 'true', case-insensitive, enables the list).
    """
    lists = {}
    current = None
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return lists
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            lists[current] = {"address": "", "members": [], "enabled": False}
            continue
        if current is None or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip().lower()
        val = val.strip()
        if key == "address":
            lists[current]["address"] = val
        elif key == "members":
            lists[current]["members"] = [m.strip() for m in val.split(",") if m.strip()]
        elif key == "enabled":
            lists[current]["enabled"] = val.lower() == "true"
    return lists


def reload_config(*_args):
    STATE["lists"] = load_config()


def handle(line):
    parts = line.split()
    if not parts:
        return "ERR"
    cmd = parts[0].upper()
    if cmd == "PING":
        return "PONG"
    if cmd == "LISTS":
        names = sorted(n for n, d in STATE["lists"].items() if d["enabled"])
        return ",".join(names) if names else "NONE"
    if cmd in ("MEMBERS", "COUNT") and len(parts) >= 2:
        entry = STATE["lists"].get(parts[1])
        if not entry or not entry["enabled"]:
            return "UNKNOWN"
        if cmd == "MEMBERS":
            return ",".join(entry["members"])
        return str(len(entry["members"]))
    return "ERR"


def serve():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(64)
    while True:
        conn, _ = srv.accept()
        try:
            conn.settimeout(5)
            data = b""
            while b"\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            line = data.split(b"\n", 1)[0].decode("utf-8", "replace").strip()
            resp = handle(line) if line else "ERR"
            conn.sendall((resp + "\n").encode("utf-8"))
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    signal.signal(signal.SIGHUP, reload_config)
    reload_config()
    with open(PIDFILE, "w") as fh:
        fh.write(str(os.getpid()))
    serve()
