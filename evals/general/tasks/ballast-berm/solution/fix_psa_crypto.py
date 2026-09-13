#!/usr/bin/env python3
"""Apply the minimal upstream fix for the ballast-berm bug.

In psa_cipher_decrypt(), the guard that rejects inputs shorter than one
AES block is specific to the CCM* no-tag algorithm and is wrong: a CCM*
message needs to be only as long as the nonce it carries (13 bytes for this
implementation's CCM* fixed nonce size), not a full 16-byte block. The
fix removes that special case so the general minimum-input check (the
algorithm's IV length) is the only length gate left.

Usage: fix_psa_crypto.py /app/src/library/psa_crypto.c
"""
import sys

BUGGY = """    if (alg == PSA_ALG_CCM_STAR_NO_TAG &&
        input_length < PSA_BLOCK_CIPHER_BLOCK_LENGTH(slot->attr.type)) {
        status = PSA_ERROR_INVALID_ARGUMENT;
        goto exit;
    } else if (input_length < PSA_CIPHER_IV_LENGTH(slot->attr.type, alg)) {
        status = PSA_ERROR_INVALID_ARGUMENT;
        goto exit;
    }"""

FIXED = """    if (input_length < PSA_CIPHER_IV_LENGTH(slot->attr.type, alg)) {
        status = PSA_ERROR_INVALID_ARGUMENT;
        goto exit;
    }"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_psa_crypto.py <path-to-psa_crypto.c>")
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if BUGGY not in text:
        print(f"ERROR: the buggy CCM* block-length check was not found in "
              f"{path}; refusing to patch", file=sys.stderr)
        return 1
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(BUGGY, FIXED))
    print("patched: CCM* decrypt now only enforces the IV-length minimum")
    return 0


if __name__ == "__main__":
    sys.exit(main())