#!/usr/bin/env python3
"""Ridgeor discrete cipher oracle.

A deliberately weak "cipher": every plaintext byte is XORed with a byte of a
secret 8-byte key K, repeating cyclically.  This is NOT a real cipher — it is a
black-box oracle an operator ships to probe a chosen-plaintext defender payload.
Because the key is deterministic and the mapping is byte-aligned, a correctly
written attacker can recover K with a handful of zero-padded queries.

The secret is resolved once, at import time, in this order:

    1. the file /app/.vault-cipher-key  (exactly 16 ASCII hex chars), then
    2. the environment variable CIPHER_ORACLE_KEY (exactly 16 hex chars), then
    3. the hard-coded default below.

Script interface:

    python3 cipher_service.py <16-hex-plaintext> -> prints hex ciphertext

Library interface:

    import cipher_service
    cipher_service.query("0000000000000000")  # -> hex ciphertext

The service accepts arbitrarily sized plaintexts (up to 4096 bytes) and is
locally deterministic, so repeated runs on the same key match.
"""

import os
import re
import sys

_KEY = bytes.fromhex("c0ffee1234abcdef")


def _load_key():
    global _KEY
    raw = None
    try:
        with open("/app/.vault-cipher-key", "rb") as fh:
            raw = fh.read().decode("ascii").strip()
    except Exception:
        raw = os.environ.get("CIPHER_ORACLE_KEY")
    if raw:
        if not re.fullmatch(r"[0-9a-fA-F]{16}", str(raw)):
            raise ValueError("key must be 16 hex chars, got %r" % (raw,))
        _KEY = bytes.fromhex(raw)


_load_key()


def query(plain_hex: str) -> str:
    """Return the hex 'cipher' of a hex plaintext under the secret key.

    ciphertext[i] = plaintext[i] XOR K[i mod 8]
    """
    if not re.fullmatch(r"[0-9a-fA-F]*", plain_hex):
        raise ValueError("plaintext must be hex")
    p = bytes.fromhex(plain_hex)
    if len(p) > 4096:
        raise ValueError("plaintext too long")
    out = bytearray(len(p))
    for i, b in enumerate(p):
        out[i] = (b ^ _KEY[i % 8])
    return bytes(out).hex()


def key_hex() -> str:
    return _KEY.hex()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: cipher_service.py <16-hex-plaintext>")
    print(query(sys.argv[1]))