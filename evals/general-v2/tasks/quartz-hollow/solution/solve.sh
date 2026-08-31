#!/bin/bash
# Oracle for quartz-hollow.
#  1. Write /app/derive.py — a generic v2 (CRMT2) key-tape decoder that
#     prints the credential for a given store directory.
#  2. Run it on /app/store to recover the credential.
#  3. Run the target application (/app/signer.py) with the recovered
#     credential so its body executes and produces the side-effect file
#     /app/releases/commit.token.
# Never reads /tests.
set -eu

cat > /app/derive.py <<'PYEOF'
#!/usr/bin/env python3
"""Derive the release credential from a v2 (CRMT2) release key tape.

Usage: python3 derive.py [store_dir]     (default /app/store)

Prints the credential as a single line on stdout.
"""
import os
import struct
import sys

ENCODINGS = {0: "raw", 1: "bitnot", 2: "hexascii"}


def decode_pad(enc: int, stored: bytes) -> bytes:
    if enc == 0:                      # raw
        return stored
    if enc == 1:                      # bit-wise complement
        return bytes(b ^ 0xFF for b in stored)
    if enc == 2:                      # ascii hex text (lowercase)
        return bytes.fromhex(stored.decode("ascii"))
    raise ValueError("unknown pad encoding %d" % enc)


def derive_from_tape(blob: bytes) -> str:
    if blob[:5] != b"CRMT2":
        raise ValueError("not a CRMT2 tape")
    off = 5
    npads, nshards = struct.unpack_from(">HH", blob, off)
    off += 4

    pads = {}
    for _ in range(npads):
        enc = blob[off]
        plen = struct.unpack_from(">H", blob, off + 1)[0]
        off += 3
        pads[len(pads)] = decode_pad(enc, blob[off:off + plen])
        off += plen

    shards = {}
    for _ in range(nshards):
        sid, pid, slen = struct.unpack_from(">HHH", blob, off)
        off += 6
        pad = pads[pid]
        shards[sid] = bytes(
            b ^ pad[i % len(pad)] for i, b in enumerate(blob[off:off + slen])
        )
        off += slen

    (order_len,) = struct.unpack_from(">H", blob, off)
    off += 2
    order = list(blob[off:off + order_len])
    return b"".join(shards[sid] for sid in order).decode("utf-8")


def main() -> None:
    store = sys.argv[1] if len(sys.argv) > 1 else "/app/store"
    with open(os.path.join(store, "tape.bin"), "rb") as fh:
        sys.stdout.write(derive_from_tape(fh.read()) + "\n")


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/derive.py

CRED="$(python3 /app/derive.py /app/store)"
echo "derived credential: $CRED"
[ -n "$CRED" ] || { echo "empty credential" >&2; exit 1; }

# Run the target application with the derived secret so its body executes and
# writes the side-effect token file.
python3 /app/signer.py "$CRED"

[ -s /app/releases/commit.token ] || { echo "side-effect file missing" >&2; exit 1; }
echo "side-effect file: $(cat /app/releases/commit.token)"
echo "quartz-hollow oracle OK"