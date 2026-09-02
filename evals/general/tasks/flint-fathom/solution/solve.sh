#!/usr/bin/env bash
# Oracle for flint-fathom. Builds every deliverable by doing the real work:
#  1. /app/fetch_media.sh (HTTP download)  -> /app/source.mp4
#  2. ffmpeg trailing tail trim           -> /app/clip.mp4
#  3. /app/detect_frames.py on clip       -> /app/events.json
#  4. /app/extract_commands.py            -> /app/commands.txt
set -euo pipefail
cd /app

# ---- 1. fetch_media.sh and run it ------------------------------------------
cat > /app/fetch_media.sh <<'SH'
#!/bin/bash
# Fetch the media mirror over HTTP into a target mp4.
set -euo pipefail
URL="${1:-http://127.0.0.1:8765/media_source.mp4}"
OUT="${2:-/app/source.mp4}"
# Serve the read-only mirror, curl it down as binary, then tear the server down.
python3 -m http.server 8765 --bind 127.0.0.1 --directory /app/fixtures >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1
curl -sf "$URL" -o "$OUT"
SH
chmod +x /app/fetch_media.sh
/app/fetch_media.sh
python3 - <<'PY'
import os
assert os.path.getsize("/app/source.mp4") > 1000, "source.mp4 too small"
print("source.mp4 bytes", os.path.getsize("/app/source.mp4"))
PY

# ---- 2. trim trailing tail into /app/clip.mp4 -------------------------------
ffmpeg -y -i /app/source.mp4 \
    -vf "select='gte(n,120)',setpts=PTS-STARTPTS" \
    -r 30 -c:v mpeg4 -q:v 2 -an /app/clip.mp4 2>/dev/null
python3 - <<'PY'
import subprocess
# sanity: count the clip frame-by-frame with OpenCV (should be ~60).
import cv2 as cv
cap = cv.VideoCapture("/app/clip.mp4")
n = 0
while True:
    ok, _ = cap.read()
    if not ok:
        break
    n += 1
cap.release()
print("clip frames =", n)
assert 58 <= n <= 62, n
PY

# ---- 3. frame analysis -> /app/events.json ----------------------------------
cat > /app/detect_frames.py <<'PY'
#!/usr/bin/env python3
"""Phantom  detector: takeoff/landing frame indices for a monocular jump clip.

The scene is a fixed flat track with one bright subject whose vertical position
variedges only by standing on (baseline) or leaving/returning to the ground.
For every frame we locate the subject and record the row of its bottom edge, then
resolve the two events with clean null semantics.
"""
import json
import sys
from collections import Counter

import cv2
import numpy as np

TARGET = np.array([255, 242, 88], dtype=np.float32)   # the subject's color


def subject_bottom(frame):
    """Return the largest row occupied by the subject, or None if absent."""
    if frame is None or frame.ndim != 3:
        return None
    diff = np.abs(frame.astype(np.float32) - TARGET).sum(axis=2)
    mask = diff < 90
    rows = np.where(mask.sum(axis=1) >= 12)[0]
    if rows.size == 0:
        return None
    return int(rows.max())


def analyze(path):
    cap = cv2.VideoCapture(path)
    bottoms = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        bottoms.append(subject_bottom(frame))
    cap.release()

    known = [b for b in bottoms if b is not None]
    if not known:
        return {"takeoff_frame": None, "landing_frame": None}

    baseline = max(known)   # resting position = lowest (largest) bottom row
    # clearly off ground: bottom row well above the resting baseline
    off = [f for f, b in enumerate(bottoms)
           if b is not None and b <= baseline - 2]
    takeoff = off[0] if off else None
    landing = None
    if off:
        for f in range(off[-1] + 1, len(bottoms)):
            b = bottoms[f]
            if b is not None and b >= baseline - 1:
                landing = f
                break
    return {"takeoff_frame": takeoff, "landing_frame": landing}


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: detect_frames.py <video.mp4> <out.json>\n")
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    obj = analyze(src)
    with open(dst, "w") as fh:
        json.dump(obj, fh)
    print(json.dumps(obj))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/detect_frames.py
python3 /app/detect_frames.py /app/clip.mp4 /app/events.json

# ---- 4. transcript -> /app/commands.txt -------------------------------------
cat > /app/extract_commands.py <<'PY'
#!/usr/bin/env python3
"""Extract the ordered user-typed commands from a session transcript."""
import re
import sys

LINE = re.compile(r"^\S+\s+USER>\s?(.*)$")


def extract_commands(path):
    cmds = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            m = LINE.match(raw.rstrip("\n"))
            if m:
                cmd = m.group(1).strip()
                if cmd:
                    cmds.append(cmd)
    return cmds


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: extract_commands.py <transcript> [out.txt]\n")
        return 2
    src = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else None
    cmds = extract_commands(src)
    text = "".join(f"{c}\n" for c in cmds)
    sys.stdout.write(text)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/extract_commands.py
python3 /app/extract_commands.py /app/fixtures/transcript.txt /app/commands.txt

echo "solution done"
exit 0