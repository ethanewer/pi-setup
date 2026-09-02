#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import json
import struct

IMG = "/workspace/evidence.dd"
with open(IMG, "rb") as f:
    img = f.read()

assert img[0:8] == b"CASEIMG1", "unexpected magic"
dir_off = struct.unpack("<Q", img[16:24])[0]

target = b"archive/corruption.txt"
found = None
off = dir_off
while off + 130 <= len(img):
    status = img[off]
    nlen = img[off + 5]
    name = img[off + 6:off + 6 + nlen]
    data_off, size = struct.unpack("<QQ", img[off + 38:off + 54])
    if name == target:
        found = (status, name, data_off, size)
    off += 130
assert found is not None, "target record not found"
status, name, data_off, size = found

content = img[data_off:data_off + size]
with open("/app/recovered.txt", "wb") as f:
    f.write(content)

import hashlib
sha = hashlib.sha256(content).hexdigest()
with open("/app/recovered.sha256", "w") as f:
    f.write(sha + "\n")

with open("/app/evidence.json", "w") as f:
    json.dump({
        "image": "/workspace/evidence.dd",
        "record_status": "0xE5",
        "name": "archive/corruption.txt",
        "offset": data_off,
        "size": size,
        "image_sha256": hashlib.sha256(img).hexdigest(),
        "recovered_sha256": sha,
    }, f, indent=2)
print("recovered", len(content), "bytes")
PY