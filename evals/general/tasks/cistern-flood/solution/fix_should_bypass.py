#!/usr/bin/env python3
"""Apply the upstream domain-boundary fix to requests.utils.

The no_proxy matcher must first try an exact hostname / host:port match
against the entry and only then compare suffixes, and a suffix comparison
must run against the entry prefixed with a leading dot so only genuine
subdomains match. Dotted entries are normalized by stripping the leading dot
before the exact match. This mirrors the bpo-39057 fix for urllib.request.
"""
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "src/requests/utils.py"

BUGGY = """            for host in no_proxy_hosts:
                if hostname.endswith(host) or host_with_port.endswith(host):
                    # The URL does match something in no_proxy, so we don't want
                    # to apply the proxies on this URL.
                    return True
"""

FIXED = """            for host in no_proxy_hosts:
                host = host.lstrip(".")
                if hostname == host or host_with_port == host:
                    return True
                host = "." + host
                if hostname.endswith(host) or host_with_port.endswith(host):
                    return True
"""


def main() -> None:
    with open(PATH, encoding="utf-8") as fh:
        source = fh.read()
    if BUGGY not in source:
        sys.exit(f"buggy matcher block not found in {PATH}; refusing to patch")
    with open(PATH, "w", encoding="utf-8") as fh:
        fh.write(source.replace(BUGGY, FIXED, 1))
    print(f"patched {PATH}")


if __name__ == "__main__":
    main()