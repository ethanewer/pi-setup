# Detect a kinematic crossing event in a video (item-074)

`/app/clip.mp4` is a synthetic 320x240 video: a **bright-yellow ball** rises
vertically (roughly along the column `x = 160`) against a dark background, and
a faint gray horizontal line marks **`y = 150`** (image rows, `y` grows
downward).  The ball is the only bright object.  The clip is 60 frames at
30 fps.

Your job: write `/app/analyze.py` that reads the video and detects the exact
moment the ball's center crosses the `y = 150` line, then writes
`/app/events.json`.  The ball is visible for most of the clip; it exits the
top of the frame only in the very last few frames, well after the crossing
event.

## Step 1 — inspect the video first

Do not pick features blindly.  Read a handful of frames with OpenCV (e.g. via
`cv2.VideoCapture`) and inspect them: note the ball's color, its size, its
per-frame displacement, the crossing line, and that the ball is present for
virtually the whole clip.  Save one or two frames as PNG and look at the pixel
values of the ball region before choosing a detection threshold.

## Step 2 — define the event exactly

For each frame `k` (0-based), locate the ball's center `(x_k, y_k)`:

- threshold the frame for the ball's bright yellow color,
- take the connected component of the largest blob,
- its centroid is `(x_k, y_k)`.

Then:

- `crossing_frame` = the first `k` with `y_k <= 150`.
- `crossing_timestamp_s` = the **interpolated** crossing time:

```
prev   = crossing_frame - 1
t      = prev + (y_prev - 150) / (y_prev - y_cross)
t_sec  = t / fps          # rounded to 3 decimals
```

- `crossing_velocity_pxps` = round( `(y_prev - y_cross) * fps` ) — an estimate
  of the vertical speed at the crossing.

## Step 3 — deliverable

Write `/app/events.json`:

```json
{
  "fps": 30,
  "frame_count": 60,
  "crossing_line_y": 150,
  "crossing_frame": <int>,
  "crossing_timestamp_s": <float rounded to 3 decimals>,
  "crossing_velocity_pxps": <int>
}
```

Then **validate on the complete clip**: re-open the file, re-run your
detector over every frame, and check that (a) the detector handles all 60
frames (frames where the ball has already left the screen may simply be marked
not visible), (b) exactly one up-crossing happens at `y = 150`, (c) the
timestamp is stable if you round up/down the interpolation.  Print a short
validation summary to stdout.

Run `/app/analyze.py` so that `/app/events.json` exists.  The video is
deterministic: the same detector run twice yields the same JSON.