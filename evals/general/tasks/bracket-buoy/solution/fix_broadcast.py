#!/usr/bin/env python3
"""Apply the upstream fix for the /32 broadcast bug to the tree at /app/src.

Two assertion-guarded edits, mirroring the upstream fix (issue #2964):

1. psutil/_common.py broadcast_addr(): returns None when the network is a
   single-host prefix (/32 for IPv4, /128 for IPv6), which has no broadcast
   address; the old code derived the "broadcast" with strict=False and got
   the host's own address back.
2. psutil/__init__.py net_if_addrs(): on POSIX the C layer hands back the
   interface's own address as the broadcast for a /32; recalculate it
   through broadcast_addr() and replace the field with None whenever the
   calculation says there is no broadcast.

Each edit requires the pending block to appear exactly once and touches only
that one location.
"""
import pathlib
import sys

SRC = pathlib.Path('/app/src')
COMMON = SRC / 'psutil' / '_common.py'
INIT = SRC / 'psutil' / '__init__.py'

OLD_COMMON = '''    if addr.family == socket.AF_INET:
        return str(
            ipaddress.IPv4Network(
                f"{addr.address}/{addr.netmask}", strict=False
            ).broadcast_address
        )
    if addr.family == socket.AF_INET6:
        return str(
            ipaddress.IPv6Network(
                f"{addr.address}/{addr.netmask}", strict=False
            ).broadcast_address
        )
'''

NEW_COMMON = '''    if addr.family == socket.AF_INET:
        net = ipaddress.IPv4Network(
            f"{addr.address}/{addr.netmask}", strict=False
        )
    elif addr.family == socket.AF_INET6:
        net = ipaddress.IPv6Network(
            f"{addr.address}/{addr.netmask}", strict=False
        )
    else:
        return None
    if net.prefixlen == net.max_prefixlen:
        return None
    return str(net.broadcast_address)
'''

OLD_INIT = '''        # On Windows broadcast is None, so we determine it via
        # ipaddress module.
        if WINDOWS and fam in {socket.AF_INET, socket.AF_INET6}:
            try:
                broadcast = _common.broadcast_addr(nt)
            except Exception as err:  # noqa: BLE001
                warn(f"broadcast_addr() failed: {err!r}")
            else:
                if broadcast is not None:
                    nt = nt._replace(broadcast=broadcast)
'''

NEW_INIT = '''        # On Windows broadcast is None, so we determine it via
        # ipaddress module. On POSIX a /32 has no broadcast address,
        # but getifaddrs() hands back the local address.
        if nt.netmask and (
            fam == socket.AF_INET or (WINDOWS and fam == socket.AF_INET6)
        ):
            try:
                calculated = _common.broadcast_addr(nt)
            except Exception as err:  # noqa: BLE001
                warn(f"broadcast_addr() failed: {err!r}")
            else:
                if calculated is None:
                    nt = nt._replace(broadcast=None)
                elif WINDOWS:
                    nt = nt._replace(broadcast=calculated)
'''


def _apply(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        print(
            f'{label}: expected exactly one occurrence of the pending '
            f'block in {path}, found {count}; aborting',
            file=sys.stderr,
        )
        return False
    path.write_text(text.replace(old, new), encoding='utf-8')
    print(f'{label}: patched {path}')
    return True


def main() -> int:
    ok = True
    ok &= _apply(COMMON, OLD_COMMON, NEW_COMMON, 'broadcast_addr()')
    ok &= _apply(INIT, OLD_INIT, NEW_INIT, 'net_if_addrs()')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())