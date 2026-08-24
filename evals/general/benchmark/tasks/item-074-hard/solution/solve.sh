#!/bin/bash
set -euo pipefail

# Oracle solution for item-074-hard:
# motion-isolate the moving ball, compute metrics per the instruction, write
# /app/events.json, then self-verify against an in-container recomputation.

cat > /app/analyze.py <<'PYEOF'
#!/usr/bin/env python3
"""Adversarial clip analysis: isolate the moving ball and find its y=150
up-crossing; validate on the complete clip."""
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


def blobs(img):
    b = img[:, :, 0].astype(int)
    g = img[:, :, 1].astype(int)
    r = img[:, :, 2].astype(int)
    mask = ((r > 180) & (g > 150) & (b < 120)).astype(np.uint8)
    n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
    out = []
    for i in range(1, n):
        out.append((float(cent[i][0]), float(cent[i][1]), int(stats[i, cv2.CC_STAT_AREA])))
    return out


def ball_trajectory(frames):
    comps = [blobs(f) for f in frames]
    # frame 0: the ball is the component whose center moves the most from
    # frame 0 to frame 1; the decoy is static.
    c0, c1 = comps[0], comps[1]
    score = []
    for (x, y, a) in c0:
        d = min((abs(y2 - y) + abs(x2 - x)) for (x2, y2, a2) in c1)
        score.append((d, (x, y, a)))
    start = max(score, key=lambda s: s[0])[1]
    traj = [(start[0], start[1])]
    prev = (start[0], start[1])
    for k in range(1, len(comps)):
        cands = [(x, y, a) for (x, y, a) in comps[k]
                 if abs(y - prev[1]) < 15 and abs(x - prev[0]) < 15]
        if not cands:
            cands = comps[k]
        c = min(cands, key=lambda c: abs(c[1] - prev[1]) + abs(c[0] - prev[0]))
        traj.append((c[0], c[1]))
        prev = (c[0], c[1])
    return traj


def main():
    frames = read_frames(CLIP)
    traj = ball_trajectory(frames)
    cf = next(k for k, (x, y) in enumerate(traj) if y <= LINE)
    prev = cf - 1
    y_prev = traj[prev][1]
    y_cross = traj[cf][1]
    t = prev + (y_prev - LINE) / (y_prev - y_cross)
    vel = (y_prev - y_cross) * FPS

    result = {
        "fps": FPS,
        "frame_count": len(frames),
        "crossing_line_y": LINE,
        "crossing_frame": cf,
        "crossing_timestamp_s": round(t / FPS, 3),
        "crossing_velocity_pxps": int(round(vel)),
        "trajectory_px": [[float(x), float(y)] for (x, y) in traj],
    }
    with open(OUT, "w") as f:
        json.dump(result, f, indent=2)

    # Step 5: validate on the complete clip.
    assert len(traj) == 60, "ball tracked every frame"
    crossings = [k for k, (x, y) in enumerate(traj) if y <= LINE]
    assert crossings and crossings[0] == cf, f"expected up-crossing at {cf}, got {crossings}"
    assert all(y > LINE for (x, y) in traj[:cf]), "earlier crossing detected"
    # timestamp stability with +/-1 frame bracketing
    t_lo = (prev - 1) + (traj[prev - 1][1] - LINE) / (traj[prev - 1][1] - y_prev)
    t_hi = cf + (y_cross - LINE) / (y_cross - traj[cf + 1][1])
    assert abs((t_hi - t_lo) / FPS) < 2.0 / FPS, "crossing unstable"
    print("validated:", result)


if __name__ == "__main__":
    main()
PYEOF

python3 /app/analyze.py

# oracle self-assert: recompute expected in-container (identical decode) and
# require near-exact agreement with the produced events.json.
python3 - <<'PYEOF'
import json
import sys

import cv2
import numpy as np

LINE, FPS = 150, 30


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


def blobs(img):
    b = img[:, :, 0].astype(int)
    g = img[:, :, 1].astype(int)
    r = img[:, :, 2].astype(int)
    mask = ((r > 180) & (g > 150) & (b < 120)).astype(np.uint8)
    n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
    return [(float(cent[i][0]), float(cent[i][1])) for i in range(1, n)]


comps = [blobs(f) for f in read_frames("/app/clip.mp4")]
c0, c1 = comps[0], comps[1]
score = [(min(abs(y2 - y) + abs(x2 - x) for (x2, y2) in c1), (x, y)) for (x, y) in c0]
start = max(score, key=lambda s: s[0])[1]
traj = [start]
for k in range(1, len(comps)):
    cands = [(x, y) for (x, y) in comps[k]
             if abs(y - traj[-1][1]) < 15 and abs(x - traj[-1][0]) < 15] or comps[k]
    traj.append(min(cands, key=lambda c: abs(c[1] - traj[-1][1]) + abs(c[0] - traj[-1][0])))

cf = next(k for k, (x, y) in enumerate(traj) if y <= LINE)
y_prev, y_cross = traj[cf - 1][1], traj[cf][1]
t = cf - 1 + (y_prev - LINE) / (y_prev - y_cross)

got = json.load(open("/app/events.json"))
assert got["crossing_frame"] == cf, (got, cf)
assert abs(got["crossing_timestamp_s"] - round(t / FPS, 3)) < 0.001, (got, t / FPS)
assert got["crossing_velocity_pxps"] == int(round((y_prev - y_cross) * FPS)), got
print("oracle events OK", got)
PYEOF