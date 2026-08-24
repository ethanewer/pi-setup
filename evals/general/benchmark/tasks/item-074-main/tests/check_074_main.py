"""Verifier for item-074-main.

Re-derives the expected event metrics from /app/clip.mp4 (the exact frames the
agent analysed), then compares /app/events.json against them.

Method (mirrors the instruction):
  - yellow mask, largest connected component, centroid per frame,
  - crossing_frame = first k with y_k <= 150,
  - interpolated timestamp and velocity from the two bracketing frames.

Prints reward (1 or 0) to stdout; always exits 0.
"""
import json
import sys

import cv2
import numpy as np

CLIP = "/app/clip.mp4"
RESULT = "/app/events.json"
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


def cents(frames):
    out = []
    for img in frames:
        b = img[:, :, 0].astype(int)
        g = img[:, :, 1].astype(int)
        r = img[:, :, 2].astype(int)
        mask = ((r > 180) & (g > 150) & (b < 120)).astype(np.uint8)
        n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
        if n <= 1:
            out.append(None)
            continue
        areas = stats[:, cv2.CC_STAT_AREA]
        idx = int(np.argmax(areas[1:])) + 1
        out.append((float(cent[idx][0]), float(cent[idx][1])))
    return out


def expected(frames):
    cs = cents(frames)
    cf = None
    for k, c in enumerate(cs):
        if c is not None and c[1] <= LINE:
            cf = k
            break
    if cf is None:
        return None
    prev = cf - 1
    y_prev = cs[prev][1]
    y_cross = cs[cf][1]
    t = prev + (y_prev - LINE) / (y_prev - y_cross)
    vel = (y_prev - y_cross) * FPS
    return {
        "fps": FPS,
        "frame_count": len(frames),
        "crossing_line_y": LINE,
        "crossing_frame": cf,
        "crossing_timestamp_s": round(t / FPS, 3),
        "crossing_velocity_pxps": int(round(vel)),
    }


def main():
    try:
        frames = read_frames(CLIP)
        exp = expected(frames)
        got = json.load(open(RESULT))
        ok = True
        if exp is None:
            ok = False
        else:
            for key in ("fps", "frame_count", "crossing_line_y"):
                if got.get(key) != exp[key]:
                    ok = False
            if got.get("crossing_frame") != exp["crossing_frame"]:
                ok = False
            ts = got.get("crossing_timestamp_s")
            if ts is None or abs(float(ts) - exp["crossing_timestamp_s"]) > 0.05:
                ok = False
            vel = got.get("crossing_velocity_pxps")
            if vel is None or abs(int(vel) - exp["crossing_velocity_pxps"]) > 15:
                ok = False
        print(1 if ok else 0)
    except Exception:
        print(0)


if __name__ == "__main__":
    main()
    sys.exit(0)