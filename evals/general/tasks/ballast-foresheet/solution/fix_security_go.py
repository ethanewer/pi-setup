#!/usr/bin/env python3
"""Apply the minimal upstream fix for the default SSRF-policy leak to
config/security/securityConfig.go in a Hugo checkout.

The default security policy for remote resource fetching must refuse
non-public destinations, and it currently leaks in three ways, all in this
file:

  1. The deny rule for IP-literal URL hosts matches only a lowercase scheme
     ("! ^https?://\\d+\\."), so "HTTP://127.0.0.1/" bypasses it. The rule
     is made case-insensitive with an inline (?i) flag.
  2. CheckAllowedHTTPAddress gates a resolved dial-time address only on
     netip.IsGlobalUnicast() && !netip.IsPrivate(), which misclassifies the
     shared/CGNAT space (100.64.0.0/10), the IETF-assignment block
     (192.0.0.0/24), TEST-NET-1/2/3, the benchmarking ranges (198.18.0.0/15,
     2001:2::/48), the reserved 240.0.0.0/4 and the IPv6 documentation
     prefixes (2001:db8::/32, 3fff::/20) as public Internet space. The gate
     is replaced by an isPublicAddr helper that denies those ranges.
  3. NAT64 prefixes (64:ff9b::/96, 64:ff9b:1::/48) embed the real IPv4
     address in the low 32 bits; isPublicAddr unwraps them recursively
     before classification, and unmap()s IPv4-mapped forms first.

The fix mirrors the upstream change: same helper, same deny rules, same
public-address semantics. Usage:

    fix_security_go.py /path/to/config/security/securityConfig.go

Exits non-zero (leaving the file unmodified) if the file is not the buggy
state the task ships, so a wrong checkout fails loudly.
"""

import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_security_go.py <securityConfig.go>", file=sys.stderr)
        return 1
    path = sys.argv[1]
    src = open(path, "r", encoding="utf-8").read()

    # 1. case-insensitive scheme on the IP-literal deny rule
    old_url_rule = "\t\t\t`! ^https?://\\d+\\.`,\n"
    new_url_rule = "\t\t\t`! (?i)^https?://\\d+\\.`,\n"
    if new_url_rule in src:
        print("already fixed (case-insensitive deny rule present)")
        fixed_url = True
    else:
        assert old_url_rule in src, "parent URL deny rule not found"
        src = src.replace(old_url_rule, new_url_rule, 1)
        fixed_url = True

    # 2. replace the IsGlobalUnicast/isPrivate gate with the isPublicAddr gate
    #    (the stray ip.Unmap() call is folded into isPublicAddr upstream)
    old_gate = (
        "\tip = ip.Unmap()\n"
        "\tif !ip.IsGlobalUnicast() || ip.IsPrivate() {\n"
        "\t\treturn deny(host)\n"
        "\t}\n"
        "\treturn nil\n"
    )
    new_gate = (
        "\tif !isPublicAddr(ip) {\n"
        "\t\treturn deny(host)\n"
        "\t}\n"
        "\treturn nil\n"
    )
    if new_gate in src and "func isPublicAddr" in src:
        print("address gate already fixed")
    else:
        assert old_gate in src, "IsGlobalUnicast gate not found"
        src = src.replace(old_gate, new_gate, 1)

    # 3. add the special-purpose range tables and the isPublicAddr helper
    anchor = "// canonicalIPv4URL rewrites an integer/hex/octal IPv4 host in rawURL to its\n"
    if "func isPublicAddr(ip netip.Addr) bool" in src:
        print("isPublicAddr helper already present")
    else:
        helpers = (
            "// Special-purpose ranges that Go classifies as global unicast and\n"
            "// non-private, but that are never reachable on the public Internet.\n"
            "var nonPublicPrefixes = []netip.Prefix{\n"
            "\tnetip.MustParsePrefix(\"100.64.0.0/10\"),   // Shared address space (CGNAT), RFC 6598.\n"
            "\tnetip.MustParsePrefix(\"192.0.0.0/24\"),    // IETF protocol assignments.\n"
            "\tnetip.MustParsePrefix(\"192.0.2.0/24\"),    // TEST-NET-1.\n"
            "\tnetip.MustParsePrefix(\"198.18.0.0/15\"),   // Benchmarking.\n"
            "\tnetip.MustParsePrefix(\"198.51.100.0/24\"), // TEST-NET-2.\n"
            "\tnetip.MustParsePrefix(\"203.0.113.0/24\"),  // TEST-NET-3.\n"
            "\tnetip.MustParsePrefix(\"240.0.0.0/4\"),     // Reserved.\n"
            "\tnetip.MustParsePrefix(\"2001:db8::/32\"),   // Documentation.\n"
            "\tnetip.MustParsePrefix(\"3fff::/20\"),       // Documentation.\n"
            "\tnetip.MustParsePrefix(\"2001:2::/48\"),     // Benchmarking.\n"
            "}\n"
            "\n"
            "// nat64Prefixes embed an IPv4 address in the low 32 bits, RFC 6052/8215.\n"
            "var nat64Prefixes = []netip.Prefix{\n"
            "\tnetip.MustParsePrefix(\"64:ff9b::/96\"),\n"
            "\tnetip.MustParsePrefix(\"64:ff9b:1::/48\"),\n"
            "}\n"
            "\n"
            "func isPublicAddr(ip netip.Addr) bool {\n"
            "\tip = ip.Unmap()\n"
            "\tfor _, p := range nat64Prefixes {\n"
            "\t\tif p.Contains(ip) {\n"
            "\t\t\tb := ip.As16()\n"
            "\t\t\treturn isPublicAddr(netip.AddrFrom4([4]byte(b[12:])))\n"
            "\t\t}\n"
            "\t}\n"
            "\tif !ip.IsGlobalUnicast() || ip.IsPrivate() {\n"
            "\t\treturn false\n"
            "\t}\n"
            "\tfor _, p := range nonPublicPrefixes {\n"
            "\t\tif p.Contains(ip) {\n"
            "\t\t\treturn false\n"
            "\t\t}\n"
            "\t}\n"
            "\treturn true\n"
            "}\n"
            "\n"
        )
        assert anchor in src, "canonicalIPv4URL anchor not found"
        src = src.replace(anchor, helpers + anchor, 1)

    open(path, "w", encoding="utf-8").write(src)
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print(f"FATAL: {e}; file left as-is", file=sys.stderr)
        raise