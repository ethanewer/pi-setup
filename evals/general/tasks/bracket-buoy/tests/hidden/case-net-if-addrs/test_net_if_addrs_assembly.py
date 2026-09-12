"""Hidden case (bracket-buoy): the /32 fix must also land where the address
tuple is assembled. On POSIX, net_if_addrs() hands back the C layer's
broadcast value directly, so a /32 interface still reports the host's own
address in the broadcast field unless that field is nulled there too (the
second half of the upstream fix). This case feeds getifaddrs()-style entries
through the public psutil.net_if_addrs() and checks the reported broadcast
field — no NET_ADMIN or real /32 interface is required, and it runs on any
Linux box. Distinct from the upstream regression test, which only calls
broadcast_addr().
"""
import psutil
import socket


def _fake_c_entries():
    # What getifaddrs() hands back for a /32 interface: the host's own
    # address lands in the broadcast slot (upstream issue #2964).
    return [
        ("fake0", socket.AF_INET, "89.234.156.160", "255.255.255.255",
         "89.234.156.160", ""),
    ]


def test_single_host_32_broadcast_field_is_none():
    orig = psutil._psplatform.net_if_addrs
    try:
        psutil._psplatform.net_if_addrs = _fake_c_entries
        addrs = psutil.net_if_addrs()
    finally:
        psutil._psplatform.net_if_addrs = orig
    entry = addrs["fake0"][0]
    assert entry.broadcast is None, entry.broadcast


def test_ordinary_8_network_keeps_its_broadcast_field():
    orig = psutil._psplatform.net_if_addrs
    try:
        psutil._psplatform.net_if_addrs = lambda: [
            ("fake1", socket.AF_INET, "127.0.0.1", "255.0.0.0",
             "127.255.255.255", ""),
        ]
        addrs = psutil.net_if_addrs()
    finally:
        psutil._psplatform.net_if_addrs = orig
    entry = addrs["fake1"][0]
    assert entry.broadcast == "127.255.255.255", entry.broadcast