#!/usr/bin/env python3
"""Sealed deployment vault service.

The vault body only executes when it is given the TRUE deploy secret.  The
secret itself is never stored here -- only its SHA-256 digest is pinned below.
When the correct secret is supplied, ``open_vault`` performs the unseal work
and writes the side-effect file ``/app/vault_out/unsealed.txt``.  There is no
other way to produce that file.
"""
import hashlib
import os
import sys

# SHA-256 of the true deploy secret.
VAULT_DIGEST = "627aeb478ab4a3b901733f1d349364d98a0a85b58f04bbd4f42651256b218bb4"
UNSEAL_NONCE = "9f2c-4b71-ae05"

OUT_DIR = "/app/vault_out"
OUT_FILE = "unsealed.txt"


def open_vault(secret):
    """Execute the vault body. Returns True only for the true deploy secret."""
    if not isinstance(secret, str):
        return False
    if hashlib.sha256(secret.encode("utf-8")).hexdigest() != VAULT_DIGEST:
        return False
    # ---- vault body: runs only when the secret is correct -----------------
    body = (
        "UNSEALED by vault_service\n"
        "secret_ok=1\n"
        "nonce=%s\n" % UNSEAL_NONCE
    )
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, OUT_FILE), "w", encoding="utf-8") as fh:
        fh.write(body)
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: vault_service.py <secret>", file=sys.stderr)
        sys.exit(2)
    ok = open_vault(sys.argv[1])
    print("VAULT OPEN" if ok else "VAULT LOCKED")
    sys.exit(0 if ok else 1)
