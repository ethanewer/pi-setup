#!/bin/bash
set -euo pipefail

# Oracle solution for item-074-main: analyzer that mirrors the instruction's
# exact algorithm, run to produce /app/events.json.

cat > /app/analyze.py <<'PYEOF'
#!/usr/bin/env python3
"""Detect the y=150 up-crossing of the bright ball in clip.mp4."""
import json

import cv2
import numpy as np

CLIP = "/app/clip.mp4"
OUT = "/app/events.json"
LINE = 150
FPS = 30


def read_frames(path):
    cap = cv2.VideoCapture(path)
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    return frames


def cent(img):
    b = img[:, :, 0].astype(int)
    g = img[:, :, 1].astype(int)
    r = img[:, :, 2].astype(int)
    mask = ((r > 180) & (g > 150) & (b < 120)).astype(np.uint8)
    n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
    if n <= 1:
        return None
    areas = stats[:, cv2.CC_STAT_AREA]
    idx = int(np.argmax(areas[1:])) + 1
    return (float(cent[idx][0]), float(cent[idx][1]))


def main():
    frames = read_frames(CLIP)
    cs = [cent(f) for f in frames]
    cf = next(k for k, c in enumerate(cs) if c is not None and c[1] <= LINE)
    prev = cf - 1
    y_prev = cs[prev][1]
    y_cross = cs[cf][1]
    t = prev + (y_prev - LINE) / (y_prev - y_cross)
    vel = (y_prev - y_cross) * FPS

    result = {
        "fps": FPS,
        "frame_count": len(frames),
        "crossing_line_y": LINE,
        "crossing_frame": cf,
        "crossing_timestamp_s": round(t / FPS, 3),
        "crossing_velocity_pxps": int(round(vel)),
    }
    with open(OUT, "w") as f:
        json.dump(result, f, indent=2)

    # validation on the complete clip
    assert len(cs) == 60, "ball must be visible every frame"
    crossings = [k for k, c in enumerate(cs) if c is not None and c[1] <= LINE]
    assert crossings and crossings[0] == cf, "crossing not at first up-crossing"
    assert all(cs[k] is None or cs[k][1] > LINE for k in range(cf)), "earlier crossing"
    print("validated:", result)


if __name__ == "__main__":
    main()
PYEOF

python3 /app/analyze.py

# oracle self-assert: recompute expected in-container with the same
# algorithm; the agent/verifier see identical decoded frames so they must
# agree exactly.
python3 - <<'PYEOF'
import json

import cv2
import numpy as np

LINE = 150
FPS = 30


def read_frames(path):
    cap = cv2.VideoCapture(path)
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    return frames


def cent(img):
    b = img[:, :, 0].astype(int)
    g = img[:, :, 1].astype(int)
    r = img[:, :, 2].astype(int)
    mask = ((r > 180) & (g > 150) & (b < 120)).astype(np.uint8)
    n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
    if n <= 1:
        return None
    areas = stats[:, cv2.CC_STAT_AREA]
    idx = int(np.argmax(areas[1:])) + 1
    return (float(cent[idx][0]), float(cent[idx][1]))


frames = read_frames("/app/clip.mp4")
cs = [cent(f) for f in frames]
cf = next(k for k, c in enumerate(cs) if c is not None and c[1] <= LINE)
prev = cf - 1
t = prev + (cs[prev][1] - LINE) / (cs[prev][1] - cs[cf][1])
vel = (cs[prev][1] - cs[cf][1]) * FPS

exp = {
    "fps": FPS,
    "frame_count": len(frames),
    "crossing_line_y": LINE,
    "crossing_frame": cf,
    "crossing_timestamp_s": round(t / FPS, 3),
    "crossing_velocity_pxps": int(round(vel)),
}
got = json.load(open("/app/events.json"))
assert got["crossing_frame"] == exp["crossing_frame"], (got, exp)
assert abs(got["crossing_timestamp_s"] - exp["crossing_timestamp_s"]) < 0.001, (got, exp)
assert abs(got["crossing_velocity_pxps"] - exp["crossing_velocity_pxps"]) < 1, (got, exp)
print("oracle events OK", got)
PYEOF