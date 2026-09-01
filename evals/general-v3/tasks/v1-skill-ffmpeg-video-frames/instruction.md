# FFmpeg video frame extraction

`/app/sample.mp4` is a small H.264 video generated from a test pattern. It has
a resolution of 160x120 and a nominal rate of 10 frames/second.

You have `ffmpeg` and `ffprobe` installed (from the Ubuntu `ffmpeg` package).

## Your task

1. Use `ffmpeg` to extract **every video frame** of `/app/sample.mp4` into the
   directory `/app/frames/` as sequentially-numbered PNG files of the form
   `/app/frames/frame_00001.png`, `/app/frames/frame_00002.png`, ... (zero-pad
   to 5 digits). Create `/app/frames/` first.
2. Count how many PNG frames were written (this should equal the actual frame
   count of the video).
3. Write `/app/frames.json` with exactly:
   ```json
   {"frames": <integer: your extracted frame count>, "width": 160, "height": 120}
   ```

You may use `ffprobe` (e.g. `-count_frames` / `nb_read_frames`) to determine the
expected frame count before extracting.

Then verify your output: `/app/frames/` must contain only the extracted PNG
frames, and `/app/frames.json` must reflect the true count and dimensions. The
verifier independently counts frames via `ffprobe`, counts PNG files in
`/app/frames/`, and checks the PNG dimensions.