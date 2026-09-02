#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import hashlib
import json
import struct

IMG = "/workspace/case.dd"
TARGET = b"data/figure.png"

img = open(IMG, "rb").read()
records = []
dir_off = struct.unpack("<Q", img[16:24])[0]
off = dir_off
while off + 128 <= len(img):
    rec = img[off:off + 128]
    status = rec[0]
    jmark = rec[1]
    nlen = rec[5]
    name = rec[6:6 + nlen]
    extents = []
    for k in range(4):
        base = 38 + k * 16
        seq = struct.unpack("<I", rec[base:base + 4])[0]
        o = struct.unpack("<Q", rec[base + 4:base + 12])[0]
        sz = struct.unpack("<I", rec[base + 12:base + 16])[0]
        extents.append((seq, o, sz))
    records.append((status, jmark, name, extents))
    off += 128

rec = [r for r in records if r[1] == 0x55 and r[2] == TARGET][0]
status, _, name, extents = rec

# assemble in the order the authoritative (0x55) record lists the fragments
blob = b"".join(img[o:o + s] for _, o, s in extents)
assert blob[:8] == b"\x89PNG\r\n\x1a\n", "reassembled bytes are not a PNG"

with open("/app/figure.png", "wb") as f:
    f.write(blob)

sha = hashlib.sha256(blob).hexdigest()
with open("/app/figure.sha256", "w") as f:
    f.write(sha + "\n")

payload = {
    "image": "/workspace/case.dd",
    "name": "data/figure.png",
    "status": "0xE5",
    "marker": "0x55",
    "extents": [{"seq": s, "offset": o, "length": l} for s, o, l in extents],
    "image_sha256": hashlib.sha256(img).hexdigest(),
    "reassembled_sha256": sha,
}
with open("/app/journal.json", "w") as f:
    json.dump(payload, f, indent=2)
print("recovered", len(blob), "bytes")
PY