#!/usr/bin/env python3
"""Validate that the agent's reproduction in the ECDSA signature-conversion
test data is a GENUINE failing reproduction of the oversized-coordinate bug:

  * at least one ecdsa_raw_to_der case and one ecdsa_der_to_raw case whose
    key_bits yields a coordinate size above the library's fixed internal
    buffers (key_bits >= 529  =>  ceil(bits/8) > 66 bytes);
  * raw->DER case: the raw input decodes to exactly 2 * ceil(bits/8) bytes
    (anything else is rejected by the pre-existing length check, which would
    not exercise this bug);
  * DER->raw case: the output buffer decodes to at least 2 * ceil(bits/8)
    bytes, so that the failure cannot be blamed on the pre-existing output
    size check (which fires on the pristine tree too and is not this bug),
    and the DER input is non-empty;
  * both cases expect MBEDTLS_ERR_ASN1_BUF_TOO_SMALL.

Prints what it found; exits 0 iff the reproduction is genuine.
"""
import math
import re
import sys

RAW_RE = re.compile(
    r'^ecdsa_raw_to_der:(\d+):"([0-9a-fA-F]*)"'
    r':"([0-9a-fA-F]*)":(\S+)$')
DER_RE = re.compile(
    r'^ecdsa_der_to_raw:(\d+):"([0-9a-fA-F]*)"'
    r':"([0-9a-fA-F]*)":(\S+)$')


def main():
    path = sys.argv[1]
    raw_cases = []
    der_cases = []
    for ln in open(path, encoding="utf-8"):
        ln = ln.strip()
        m = RAW_RE.match(ln)
        if m:
            raw_cases.append((int(m.group(1)), m.group(2), m.group(3),
                              m.group(4)))
            continue
        m = DER_RE.match(ln)
        if m:
            der_cases.append((int(m.group(1)), m.group(2), m.group(3),
                              m.group(4)))

    oversized_raw = [c for c in raw_cases if c[0] >= 529]
    oversized_der = [c for c in der_cases if c[0] >= 529]
    ok = True

    def coord(bits):
        return math.ceil(bits / 8)

    print(f"raw_to_der cases: {len(raw_cases)} total, "
          f"{len(oversized_raw)} oversized (bits>=529)")
    print(f"der_to_raw cases: {len(der_cases)} total, "
          f"{len(oversized_der)} oversized (bits>=529)")

    for bits, rawhex, _derhex, ret in oversized_raw:
        want = 2 * coord(bits)
        have = len(rawhex) // 2
        if ret != "MBEDTLS_ERR_ASN1_BUF_TOO_SMALL":
            print(f"FAIL raw_to_der:{bits} expects {ret}, must expect "
                  f"MBEDTLS_ERR_ASN1_BUF_TOO_SMALL")
            ok = False
        if have != want:
            print(f"FAIL raw_to_der:{bits} raw is {have} bytes, expected "
                  f"{want}")
            ok = False
    for bits, derhex, rawhex, ret in oversized_der:
        c = coord(bits)
        out = len(rawhex) // 2
        if ret != "MBEDTLS_ERR_ASN1_BUF_TOO_SMALL":
            print(f"FAIL der_to_raw:{bits} expects {ret}, must expect "
                  f"MBEDTLS_ERR_ASN1_BUF_TOO_SMALL")
            ok = False
        if out < 2 * c:
            print(f"FAIL der_to_raw:{bits} output buffer is {out} bytes, "
                  f"must be >= {2 * c} so the pre-existing size check does "
                  f"not fire")
            ok = False
        if len(derhex) == 0:
            print(f"FAIL der_to_raw:{bits} has an empty DER input")
            ok = False
        elif derhex[:2] != "30":
            print(f"FAIL der_to_raw:{bits} DER does not start with the "
                  f"expected ASN.1 sequence tag (30)")
            ok = False

    if not oversized_raw:
        print("FAIL no oversized (bits>=529) ecdsa_raw_to_der case found")
        ok = False
    if not oversized_der:
        print("FAIL no oversized (bits>=529) ecdsa_der_to_raw case found")
        ok = False

    print("RESULT:", "GENUINE" if ok else "NOT-A-REPRO")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()