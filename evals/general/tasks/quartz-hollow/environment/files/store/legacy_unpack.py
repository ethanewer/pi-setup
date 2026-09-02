#!/usr/bin/env python3
"""legacy_unpack.py -- reference reader for v1 (CRMT1) release key tapes.

This is the tool the release team used before the writer was upgraded.
It handles ONLY the v1 layout documented in TAPE-FORMAT.txt:

  * every pad is stored raw (pad_enc is always 0 in v1),
  * every shard is masked with pad_id == shard_id,
  * plaintext order equals shard file order (the manifest is ignored).

Run on anything else (e.g. a newer tape) it aborts at the magic check.
Usage: python3 legacy_unpack.py <tape.bin>
"""
import struct
import sys


def unpack_v1(data: bytes) -> bytes:
    if data[:5] != b"CRMT1":
        raise SystemExit("legacy_unpack: not a CRMT1 tape (newer writer?)")
    off = 5
    (npads, nshards) = struct.unpack_from(">HH", data, off)
    off += 4

    pads = []
    for _ in range(npads):
        enc = data[off]
        plen = struct.unpack_from(">H", data, off + 1)[0]
        off += 3
        pads.append(data[off:off + plen])   # v1: always raw
        off += plen

    shards = []
    for _ in range(nshards):
        sid, pid, slen = struct.unpack_from(">HHH", data, off)
        off += 6
        body = data[off:off + slen]
        off += slen
        pad = pads[pid]
        plain = bytes(b ^ pad[i % len(pad)] for i, b in enumerate(body))
        shards.append(plain)                # v1: file order == plaintext order

    return b"".join(shards)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: legacy_unpack.py <tape.bin>")
    with open(sys.argv[1], "rb") as fh:
        blob = fh.read()
    sys.stdout.write(unpack_v1(blob).decode("utf-8"))
