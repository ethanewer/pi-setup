#!/bin/bash
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

REWARD=$(python3 - <<'PY'
import hashlib
import json
import struct

IMG = "/workspace/case.dd"
ORIGINAL_IMAGE_SHA = "b351cba6976baf806e08182249f3a90afcccef173acac1939116f82dcc837ee6"
TARGET = b"data/figure.png"

results = {}

try:
    with open(IMG, "rb") as f:
        img = f.read()
    results["image_intact"] = hashlib.sha256(img).hexdigest() == ORIGINAL_IMAGE_SHA
except Exception:
    results["image_intact"] = False

# derive expected reassembly from the authoritative 0x55 record in the image
exp = None
exp_extents = None
try:
    dir_off = struct.unpack("<Q", img[16:24])[0]
    off = dir_off
    while off + 128 <= len(img):
        rec = img[off:off + 128]
        jmark = rec[1]
        nlen = rec[5]
        name = rec[6:6 + nlen]
        if jmark == 0x55 and name == TARGET:
            extents = []
            for k in range(4):
                base = 38 + k * 16
                seq = struct.unpack("<I", rec[base:base + 4])[0]
                o = struct.unpack("<Q", rec[base + 4:base + 12])[0]
                sz = struct.unpack("<I", rec[base + 12:base + 16])[0]
                extents.append((seq, o, sz))
            exp = b"".join(img[o:o + s] for _, o, s in extents)
            exp_extents = extents
            break
        off += 128
except Exception:
    pass
exp_sha = hashlib.sha256(exp).hexdigest() if exp else ""

try:
    with open("/app/figure.png", "rb") as f:
        got = f.read()
    results["png_exact"] = (got == exp)
except Exception:
    results["png_exact"] = False

try:
    got_sha = open("/app/figure.sha256").read().strip().lower()
    results["sha256_match"] = (got_sha == exp_sha)
except Exception:
    results["sha256_match"] = False

try:
    j = json.load(open("/app/journal.json"))
    ext_ok = (j.get("name") == "data/figure.png"
              and j.get("status") == "0xE5"
              and j.get("marker") == "0x55"
              and len(j.get("extents", [])) == 4
              and [ (e["seq"], e["offset"], e["length"]) for e in j["extents"] ] == [ (s, o, l) for s, o, l in (exp_extents or []) ])
    results["journal_meta"] = ext_ok
    results["journal_image_sha"] = j.get("image_sha256") == ORIGINAL_IMAGE_SHA
    results["journal_rec_sha"] = j.get("reassembled_sha256") == exp_sha
except Exception:
    results["journal_meta"] = False
    results["journal_image_sha"] = False
    results["journal_rec_sha"] = False

checks = ["image_intact", "png_exact", "sha256_match",
          "journal_meta", "journal_image_sha", "journal_rec_sha"]
score = sum(1 for c in checks if results.get(c)) / len(checks)
print(f"{score:.4f}")
PY
)
printf '%s\n' "$REWARD" > /logs/verifier/reward.txt
exit 0