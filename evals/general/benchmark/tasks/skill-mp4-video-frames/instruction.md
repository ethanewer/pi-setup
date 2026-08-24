In `/app` there is an mp4 file `video.mp4` generated from 50 solid-colour frames: 10 frames per second, 5 seconds total, each frame 16x16 pixels. The frames are grouped into five colour bands in time order:

- 0.0–0.9 s: pure red `(255, 0, 0)`
- 1.0–1.9 s: pure green `(0, 255, 0)`
- 2.0–2.9 s: pure blue `(0, 0, 255)`
- 3.0–3.9 s: white `(255, 255, 255)`
- 4.0–4.9 s: black `(0, 0, 0)`

Write a Python script `/app/frame.py` that:

1. Uses `ffmpeg` (already installed) to **decode exactly the video frame whose display timestamp is 2.5 s** and dump it to raw 24-bit RGB bytes (16x16 pixels).
2. Reads those 768 bytes and computes the **average colour** of the frame as three integers `(r, g, b)` = per-channel rounded means.
3. Writes `/app/report.txt` containing exactly one line:

```
<r> <g> <b>
```

where `<r>`, `<g>`, `<b>` are the rounded average channel values separated by spaces.

Hint: extract the raw frame with a command like
`ffmpeg -y -i /app/video.mp4 -ss 2.5 -frames:v 1 -f rawvideo -pix_fmt rgb24 -s 16x16 /app/frame.rgb`
then read `/app/frame.rgb`. Decide which colour band the extracted frame belongs to and report its average colour.

Run the script so `/app/report.txt` exists with the correct colour values.