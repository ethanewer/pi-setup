#!/usr/bin/env python3
"""MDS gateway: a long-lived dependent server.

Listens on <mds.address>:<mds.rpc.port + 10>. It is the service that the rest
of the single-node cluster depends on. On each connection it answers a
readiness banner and closes. After binding, it writes a readiness marker
(/app/run/gateway.ready) that start.sh polls, then idles forever.

Protocol: a connecting client reads one CRLF-terminated line. The expected
banner is exactly:  MDS-GATEWAY-READY
"""
import os
import re
import signal
import socket
import time
import xml.etree.ElementTree as ET

BANNER = b"MDS-GATEWAY-READY\n"
HOST_INTERFACE = "127.0.0.1"

# Ignore SIGTERM/SIGINT so the *long-lived* server is not killed silently by
# the supervising shell's foreground/background bookkeeping.
for _sig in (signal.SIGTERM, signal.SIGINT):
    try:
        signal.signal(_sig, signal.SIG_IGN)
    except Exception:
        pass


def _prop(root, name):
    for p in root.findall(".//property"):
        if p.findtext("name") == name:
            return (p.findtext("value") or "").strip()
    return ""


def main():
    config_path = "/app/config/core.xml"
    if not os.path.isfile(config_path):
        raise SystemExit("missing %s" % config_path)

    root = ET.parse(config_path).getroot()
    address = _prop(root, "mds.address") or HOST_INIT
    rpc_port = int(_prop(root, "mds.rpc.port") or "0")
    if rpc_port <= 0:
        raise SystemExit("bad/empty mds.rpc.port in %s" % config_path)
    port = rpc_port + 10

    os.makedirs("/app/run", exist_ok=True)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((address, port))
    srv.listen(16)

    with open("/app/run/gateway.pid", "w") as fh:
        fh.write(str(os.getpid()))
    # readiness marker = "wait for a readiness signal"
    with open("/app/run/gateway.ready", "w") as fh:
        fh.write("ready addr=%s port=%d\n" % (address, port))

    print("gateway READY addr=%s port=%d" % (address, port), flush=True)

    while True:
        try:
            conn, _ = srv.accept()
        except Exception:
            time.sleep(0.2)
            continue
        try:
            conn.sendall(BANNER)
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()