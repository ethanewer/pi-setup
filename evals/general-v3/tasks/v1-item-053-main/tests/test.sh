#!/bin/bash
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

REWARD=$(python3 - <<'PY'
import hashlib
import json
import struct

IMG = "/workspace/evidence.dd"
ORIGINAL_IMAGE_SHA = "2fcc55ad4fbd0385a7eca61e23349a30ae1af4f83eeb11733c767b1e7c473115"

results = {}

# 1. evidence image unmodified
try:
    with open(IMG, "rb") as f:
        img = f.read()
    results["image_intact"] = hashlib.sha256(img).hexdigest() == ORIGINAL_IMAGE_SHA
except Exception:
    results["image_intact"] = False

# 2. derive expected content + metadata from the image itself
expected_bytes = None
expected_meta = None
try:
    dir_off = struct.unpack("<Q", img[16:24])[0]
    off = dir_off
    target = b"archive/corruption.txt"
    while off + 130 <= len(img):
        status = img[off]
        nlen = img[off + 5]
        name = img[off + 6:off + 6 + nlen]
        data_off, size = struct.unpack("<QQ", img[off + 38:off + 54])
        if name == target:
            expected_bytes = img[data_off:data_off + size]
            expected_meta = (status, name, data_off, size)
            break
        off += 130
except Exception:
    pass
exp_sha = hashlib.sha256(expected_bytes).hexdigest() if expected_bytes else ""

# 3. recovered.txt
try:
    with open("/app/recovered.txt", "rb") as f:
        got_bytes = f.read()
    results["recovered_exact"] = (got_bytes == expected_bytes)
except Exception:
    results["recovered_exact"] = False

# 4. recovered.sha256
try:
    with open("/app/recovered.sha256") as f:
        got_sha = f.read().strip().lower()
    results["sha256_match"] = (got_sha == exp_sha)
except Exception:
    results["sha256_match"] = False

# 5. evidence.json
try:
    ev = json.load(open("/app/evidence.json"))
    status, name, data_off, size = expected_meta or (0xE5, b"archive/corruption.txt", 3584, 0)
    results["json_meta"] = (ev.get("name") == "archive/corruption.txt"
                            and ev.get("record_status") == "0xE5"
                            and ev.get("offset") == data_off
                            and ev.get("size") == size)
    results["json_image_sha"] = ev.get("image_sha256") == ORIGINAL_IMAGE_SHA
    results["json_rec_sha"] = ev.get("recovered_sha256") == exp_sha
except Exception:
    results["json_meta"] = False
    results["json_image_sha"] = False
    results["json_rec_sha"] = False

checks = ["image_intact", "recovered_exact", "sha256_match",
          "json_meta", "json_image_sha", "json_rec_sha"]
score = sum(1 for c in checks if results.get(c)) / len(checks)
print(f"{score:.4f}")
PY
)
printf '%s\n' "$REWARD" > /logs/verifier/reward.txt
exit 0