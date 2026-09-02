#!/bin/bash
# Oracle for cinder-fleet: write the extract.py recovery tool (the real work),
# then RUN it on the shipped workspace to land the deliverables in /app.
# Never reads /tests.
set -eu

cat > /app/extract.py <<'PY'
#!/usr/bin/env python3
"""Recover the gate-controller service token from a firmware TLV dump.

Usage: python3 extract.py <workspace_dir> <out_dir>
Writes secret.txt, pin.txt, records.json into <out_dir>.
"""
import json
import os
import sys
import zlib

TAG_TOKEN = 0x03
TAG_CRC = 0x04


def xor(data: bytes, key: bytes) -> bytes:
    return bytes(b ^ key[i % len(key)] for i, b in enumerate(data))


def parse_records(data: bytes):
    """Parse TLV records; stop at a truncated tail record."""
    recs = []
    i = 0
    while i + 2 <= len(data):
        tag = data[i]
        ln = data[i + 1]
        if i + 2 + ln > len(data):
            break
        recs.append((tag, ln, data[i + 2:i + 2 + ln]))
        i += 2 + ln
    return recs


def recover(records):
    crc_values = {int.from_bytes(p, "little") for t, _, p in records if t == TAG_CRC and len(p) == 4}
    token_payloads = [p for t, _, p in records if t == TAG_TOKEN]
    for payload in token_payloads:
        for n in range(10000):
            pin = b"%04d" % n
            plain = xor(payload, pin)
            if (zlib.crc32(plain) & 0xFFFFFFFF) not in crc_values:
                continue
            if not all(32 <= b < 127 for b in plain):
                continue
            return pin.decode(), plain.decode("ascii")
    raise SystemExit("no TOKEN/CRC32 pair validated")


def main():
    workspace, out_dir = sys.argv[1], sys.argv[2]
    with open(os.path.join(workspace, "dump.bin"), "rb") as fh:
        data = fh.read()
    records = parse_records(data)
    pin, payload = recover(records)
    secret = payload.strip().lower()
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "secret.txt"), "w") as fh:
        fh.write(secret + "\n")
    with open(os.path.join(out_dir, "pin.txt"), "w") as fh:
        fh.write(pin + "\n")
    with open(os.path.join(out_dir, "records.json"), "w") as fh:
        json.dump(
            {
                "records": [{"tag": "%02x" % t, "length": ln} for t, ln, _ in records],
                "pin": pin,
                "secret": secret,
            },
            fh,
            indent=2,
        )
    print("recovered pin=%s secret=%s (%d records)" % (pin, secret, len(records)))


if __name__ == "__main__":
    main()
PY

chmod +x /app/extract.py

python3 /app/extract.py /app/workspace /app

echo "solve.sh done"
ls -l /app/extract.py /app/secret.txt /app/pin.txt /app/records.json
