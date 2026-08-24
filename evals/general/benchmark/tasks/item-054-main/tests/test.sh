#!/bin/bash
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

REWARD=$(python3 - <<'PY'
import os
import re
import subprocess
import sys

SCENES_DIR = "/tests/scenes"
REF_SRC = "/tests/render_ref.c"
TRACER = "/app/pov/tracer"

results = {}

# build the reference ground-truth binary from the verifier's own copy
rc = subprocess.run(["gcc", "-O2", "-o", "/tmp/ref", REF_SRC],
                    capture_output=True, text=True)
if rc.returncode != 0:
    print("0.0000")
    sys.exit(0)

def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
    if not m:
        return None
    w, h = int(m.group(1)), int(m.group(2))
    body = data[m.end():]
    if len(body) != w * h * 3:
        return None
    return w, h, body

scenes = sorted(f for f in os.listdir(SCENES_DIR)
               if f.endswith(".pov") and f != "big.pov")

# source presence
results["source_exists"] = os.path.isfile("/app/pov/tracer.c")
results["binary_exists"] = os.path.isfile(TRACER) and os.access(TRACER, os.X_OK)

n_scene = 0
for scene in scenes:
    ref_out = f"/tmp/ref_{scene}.ppm"
    r1 = subprocess.run(["/tmp/ref", os.path.join(SCENES_DIR, scene), ref_out],
                        capture_output=True)
    if r1.returncode != 0:
        results[scene] = False
        continue
    got_out = f"/tmp/got_{scene}.ppm"
    r2 = subprocess.run([TRACER, os.path.join(SCENES_DIR, scene), got_out],
                        capture_output=True)
    if r2.returncode != 0:
        results[scene] = False
        continue
    ref = read_ppm(ref_out)
    got = read_ppm(got_out)
    if ref is None or got is None or ref[:2] != got[:2]:
        results[scene] = False
        continue
    total = len(ref[2])
    diff = sum(1 for x, y in zip(ref[2], got[2]) if x != y)
    results[scene] = (diff / total) < 0.005
    n_scene += 1

# render-time check on the big scene
time_ok = False
try:
    big = os.path.join(SCENES_DIR, "big.pov")
    r = subprocess.run(["timeout", "5", TRACER, big, "/tmp/big_ppm.ppm"],
                       capture_output=True, timeout=20)
    if r.returncode == 0 and os.path.exists("/tmp/big_ppm.ppm"):
        ref_big = subprocess.run(["/tmp/ref", big, "/tmp/big_ref.ppm"], capture_output=True)
        if ref_big.returncode == 0:
            rb = read_ppm("/tmp/big_ref.ppm")
            gb = read_ppm("/tmp/big_ppm.ppm")
            if rb and gb and rb[:2] == gb[:2]:
                diff = sum(1 for x, y in zip(rb[2], gb[2]) if x != y)
                time_ok = diff / len(rb[2]) < 0.005
except Exception:
    pass
results["fast_big"] = time_ok

checks = ["source_exists", "binary_exists", "fast_big"] + scenes
score = sum(1 for c in checks if results.get(c)) / len(checks)
print(f"{score:.4f}")
PY
)
printf '%s\n' "$REWARD" > /logs/verifier/reward.txt
exit 0