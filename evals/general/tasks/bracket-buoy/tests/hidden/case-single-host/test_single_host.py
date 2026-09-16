"""Hidden case (bracket-buoy): single-host networks must have NO broadcast.

A /32 IPv4 network and a /128 IPv6 network have exactly one address and no
broadcast by definition. These inputs deliberately differ from the upstream
regression test (which only covers 89.234.156.160/32).
"""
import socket

from psutil._common import broadcast_addr
from psutil._ntuples import snicaddr


def _v4(address, netmask):
    return snicaddr(socket.AF_INET, address, netmask, None, None)


def _v6(address, netmask):
    return snicaddr(socket.AF_INET6, address, netmask, None, None)


def test_ipv4_32_variants_have_no_broadcast():
    for address, netmask in [
        ('10.44.0.37', '255.255.255.255'),
        ('172.16.9.1', '255.255.255.255'),
        ('198.51.100.23', '255.255.255.255'),
        ('203.0.113.254', '255.255.255.255'),
    ]:
        assert broadcast_addr(_v4(address, netmask)) is None, address


def test_ipv6_128_single_host_has_no_broadcast():
    # Prefix-length netmask form, as broadcast_addr() accepts for IPv6.
    for address in ['2001:db8::1', 'fe80::1', '::1']:
        assert broadcast_addr(_v6(address, '128')) is None, address


def test_ipv6_128_when_address_is_full_width():
    # An explicitly expanded single-host address.
    got = broadcast_addr(
        _v6('2001:0db8:0000:0000:0000:0000:0000:0002', '128')
    )
    assert got is None