"""Hidden case (bracket-buoy): ordinary networks keep their broadcasts.

Guards against a fix that nulls the broadcast everywhere instead of only
for single-host prefixes: /8-/31 IPv4 and /64 IPv6 networks still produce
their real broadcast addresses, and entries without a netmask (or of an
unrelated family) stay None. Inputs differ from the upstream regression
test (which uses 10.1.1.86/24 and 172.20.10.7/28).
"""
import socket

from psutil._common import broadcast_addr
from psutil._ntuples import snicaddr


def _v4(address, netmask):
    return snicaddr(socket.AF_INET, address, netmask, None, None)


def _v6(address, netmask):
    return snicaddr(socket.AF_INET6, address, netmask, None, None)


def test_ipv4_ordinary_prefixes_keep_their_broadcast():
    cases = [
        ('10.0.0.5', '255.0.0.0', '10.255.255.255'),          # /8
        ('172.16.1.1', '255.255.0.0', '172.16.255.255'),      # /16
        ('192.168.1.7', '255.255.255.0', '192.168.1.255'),    # /24
        ('192.0.2.33', '255.255.255.192', '192.0.2.63'),      # /26
        ('203.0.113.4', '255.255.255.254', '203.0.113.5'),    # /31
    ]
    for address, netmask, expected in cases:
        assert broadcast_addr(_v4(address, netmask)) == expected, address


def test_ipv6_64_keeps_its_broadcast():
    got = broadcast_addr(_v6('2001:db8:85a3::8a2e:370:7334', '64'))
    assert got == '2001:db8:85a3:0:ffff:ffff:ffff:ffff'


def test_no_netmask_yields_none():
    assert broadcast_addr(_v4('10.0.0.1', None)) is None
    assert broadcast_addr(_v6('2001:db8::1', None)) is None


def test_unrelated_family_yields_none():
    # Ethernet (AF_PACKET) entries never carry a broadcast.
    ether = snicaddr(socket.AF_PACKET, 'aa:bb', 'ff:ff', None, None)
    assert broadcast_addr(ether) is None
    empty = snicaddr(0, None, None, None, None)
    assert broadcast_addr(empty) is None