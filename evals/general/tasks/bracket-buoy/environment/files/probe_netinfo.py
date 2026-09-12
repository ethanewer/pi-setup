#!/usr/bin/env python3
"""Probe for bracket-buoy: what is reported as the broadcast of a /32 net?

A /32 (netmask 255.255.255.255) IPv4 address is a single-host network: it
has no broadcast address by definition. On hosts with such an interface
(VPNs, cloud instances) the networking-addresses function currently fills
the broadcast field with the interface's own address -- a nonsense value
equal to the host IP. This probe prints what the checked-out tree computes
and asserts the correct semantics. Exit code 0 means the tree behaves
correctly; non-zero means the bug is present.

Run:
    python3 /app/probe_netinfo.py
"""
import socket
import sys

import psutil
from psutil._common import broadcast_addr
from psutil._ntuples import snicaddr


def main() -> int:
    # The exact ntuple net_if_addrs() builds for a /32 interface.
    single_host = snicaddr(
        socket.AF_INET, '89.234.156.160', '255.255.255.255', None, None
    )
    got = broadcast_addr(single_host)
    print(f"broadcast_addr() for 89.234.156.160/32 -> {got!r}")
    if got is not None:
        print(
            f"BUG: a /32 network has no broadcast address, got {got!r} "
            "instead of None"
        )
        return 1

    # A normal /8 network must still produce its real broadcast.
    loopback = snicaddr(socket.AF_INET, '127.0.0.1', '255.0.0.0', None, None)
    print(f"broadcast_addr() for 127.0.0.1/8     -> {broadcast_addr(loopback)!r}")
    if broadcast_addr(loopback) != '127.255.255.255':
        print("BUG: the /8 broadcast value changed")
        return 1

    # Live look at the loopback interface through the public API.
    for nic, addrs in psutil.net_if_addrs().items():
        for a in addrs:
            if a.family == socket.AF_INET:
                print(
                    f"live: {nic}: {a.address}/{a.netmask} "
                    f"broadcast={a.broadcast!r}"
                )
    print("probe OK")
    return 0


if __name__ == '__main__':
    sys.exit(main())