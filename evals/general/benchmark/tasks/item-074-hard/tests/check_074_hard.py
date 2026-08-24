"""Verifier for item-074-hard.

Re-derives the expected metrics from /app/clip.mp4 using the same decoding the
agent saw (motion-isolated moving blob, disc centroid per frame), then checks
the agent's /app/events.json:

  - fps / frame_count / crossing_line_y exact,
  - crossing_frame exact,
  - crossing_timestamp_s within 0.05 s,
  - crossing_velocity_pxps within 15 px/s,
  - trajectory_px within 5 px per frame of the reference ball trajectory.

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
    """Motion-isolate the moving blob and track its centroid through the clip."""
    comps = [blobs(f) for f in frames]
    if not comps:
        return None
    # frame 0: the moving blob is the component whose center moves most
    # between frame 0 and frame 1 (decoy is static).
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


def expected(frames):
    traj = ball_trajectory(frames)
    if traj is None:
        return None
    cf = None
    for k, (x, y) in enumerate(traj):
        if y <= LINE:
            cf = k
            break
    if cf is None:
        return None
    prev = cf - 1
    y_prev = traj[prev][1]
    y_cross = traj[cf][1]
    t = prev + (y_prev - LINE) / (y_prev - y_cross)
    vel = (y_prev - y_cross) * FPS
    return {
        "fps": FPS,
        "frame_count": len(frames),
        "crossing_line_y": LINE,
        "crossing_frame": cf,
        "crossing_timestamp_s": round(t / FPS, 3),
        "crossing_velocity_pxps": int(round(vel)),
        "trajectory_px": [[float(x), float(y)] for (x, y) in traj],
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
            got_traj = got.get("trajectory_px")
            if not isinstance(got_traj, list) or len(got_traj) != len(exp["trajectory_px"]):
                ok = False
            else:
                for (gx, gy), (ex, ey) in zip(got_traj, exp["trajectory_px"]):
                    if abs(float(gx) - ex) > 5.0 or abs(float(gy) - ey) > 5.0:
                        ok = False
                        break
        print(1 if ok else 0)
    except Exception:
        print(0)


if __name__ == "__main__":
    main()
    sys.exit(0)