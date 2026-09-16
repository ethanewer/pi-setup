#!/usr/bin/env python3
"""Functional contract checks for the /32 broadcast fix (run under pytest).

These assertions mirror the project's own upstream regression test for the
bug (TestCommonModule::test_broadcast_addr_single_host in the fix commit,
which asserts that a single-host /32 IPv4 network yields no broadcast
address) plus ordinary-network guards. The verifier additionally runs the
upstream test itself, the project's own suite, and hidden cases.
"""
import socket

from psutil._common import broadcast_addr
from psutil._ntuples import snicaddr


def _v4(address, netmask):
    return snicaddr(socket.AF_INET, address, netmask, None, None)


def _v6(address, netmask):
    return snicaddr(socket.AF_INET6, address, netmask, None, None)


def test_single_host_32_has_no_broadcast():
    # The upstream regression test's exact input.
    nt = snicaddr(
        socket.AF_INET, '89.234.156.160', '255.255.255.255', None, None
    )
    assert broadcast_addr(nt) is None


def test_ordinary_broadcasts_are_kept():
    assert broadcast_addr(_v4('10.1.1.86', '255.255.255.0')) == '10.1.1.255'
    assert (
        broadcast_addr(_v4('172.20.10.7', '255.255.255.240'))
        == '172.20.10.15'
    )
    assert broadcast_addr(_v4('127.0.0.1', '255.0.0.0')) == '127.255.255.255'


def test_ipv6_128_has_no_broadcast():
    assert broadcast_addr(_v6('2001:db8::1', '128')) is None