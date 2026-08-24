# Detect a kinematic crossing in an adversarial clip (item-074, hard)

`/app/clip.mp4` is a synthetic 320x240 video, 60 frames at 30 fps.  There are
**two** bright-yellow discs on the dark background:

- **the ball** — small, rises roughly along the column `x = 160`,
- **a static decoy** — a larger, same-color disc that **never moves**.

A faint gray horizontal line marks the crossing line at `y = 150` (image rows,
`y` grows downward).  Near the crossing line the ball moves only ~1 px per
frame, and every frame also has small sensor-like noise.

Your job: write `/app/analyze.py` that reads the video, **isolates the moving
ball**, and reports (a) exactly when its center crosses `y = 150`, plus (b) the
ball's full trajectory so the metric is validated on the complete clip.

## Step 1 — inspect the video before choosing features

Read frames with OpenCV and inspect them before writing any detector.  Save a
couple of frames as PNG and actually look: you will see **two** yellow discs —
one moves, one does not.  A detector that simply takes the biggest bright blob
will lock onto the static decoy and produce a bogus, constant "crossing".  You
must notice this and design around it.

## Step 2 — isolate the moving object

- Threshold each frame for the ball's bright-yellow color.
- Find the connected components (blobs) per frame.
- The **moving** blob is the one whose centroid changes between consecutive
  frames (the decoy's centroid is constant).  Use the complete clip for this:
  start from the sweep where the ball moves most, then track its centroid from
  frame to frame through the whole clip.

## Step 3 — define the event exactly

From the ball's centroid sequence `(x_k, y_k)` across all `frame_count` frames:

- `crossing_frame` = first `k` with `y_k <= 150`.
- interpolated crossing:
```
prev = crossing_frame - 1
t    = prev + (y_prev - 150) / (y_prev - y_cross)
crossing_timestamp_s = t / fps          # rounded to 3 decimals
```
- `crossing_velocity_pxps = round( (y_prev - y_cross) * (fps) )`.

## Step 4 — deliverable

Write `/app/events.json`:

```json
{
  "fps": 30,
  "frame_count": 60,
  "crossing_line_y": 150,
  "crossing_frame": <int>,
  "crossing_timestamp_s": <float rounded to 3>,
  "crossing_velocity_pxps": <int>,
  "trajectory_px": [[x_0, y_0], [x_1, y_1], ...]
}
```

`trajectory_px` has exactly `frame_count` entries (one `[x, y]` per frame) for
the **moving** ball's centroid.

## Step 5 — validate metrics on the complete clip

Re-open the clip, rerun your detector, and confirm: the ball is tracked every
frame, the decoy was never used, there is exactly one up-crossing at `y=150`,
the interpolated timestamp is stable (recompute with frames `±1`), and the
trajectory array length equals `frame_count`.  Print a validation summary.

Run `/app/analyze.py` so `/app/events.json` exists.  The clip is deterministic
(the noise is fixed), so the same detector rerun gives the same JSON.