#!/usr/bin/env python3
"""MDS gateway client health-check.

A drop-in client compatible with the running gateway server. Connects to
<mds.address>:<mds.rpc.port + 10>, reads one line and compares with the
expected readiness banner.

Exit code 0 = the gateway is reachable and answered the banner; else 1.
"""
import os
import socket
import sys
import xml.etree.ElementTree as ET

EXPECTED = b"MDS-GATEWAY-READY"


def main():
    config_path = "/app/config/core.xml"
    root = ET.parse(config_path).getroot()
    address = None
    rpc_port = None
    for p in root.findall(".//property"):
        if p.findtext("name") == "mds.address":
            address = (p.findtext("value") or "").strip()
        if p.findtext("name") == "mds.rpc.port":
            rpc_port = (p.findtext("value") or "").strip()
    if not address or not rpc_port:
        print("client_check: cannot read config", file=sys.stderr)
        return 1
    port = int(rpc_port) + 10
    try:
        s = socket.create_connection((address, port), timeout=5)
        data = s.recv(64)
        s.close()
    except Exception as exc:
        print("client_check: connect fail: %r" % exc, file=sys.stderr)
        return 1
    if not data.startswith(EXPECTED):
        print("client_check: bad banner %r" % data, file=sys.stderr)
        return 1
    print("client_check: gateway OK banner=%s" % data.decode().strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())