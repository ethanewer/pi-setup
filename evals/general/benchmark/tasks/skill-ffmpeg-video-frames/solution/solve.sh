#!/bin/bash
set -euo pipefail

rm -rf /app/frames
mkdir -p /app/frames
ffmpeg -y -i /app/sample.mp4 -vsync 0 /app/frames/frame_%05d.png 2>/tmp/ffout.txt

# determine actual frame count
actual=$(ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=nb_read_frames -of csv=p=0 /app/sample.mp4 2>/dev/null | head -1)
actual=${actual:-0}

# count extracted PNGs
n=$(ls -1 /app/frames/frame_*.png 2>/dev/null | wc -l)

echo "{\"frames\": $n, \"width\": 160, \"height\": 120}" > /app/frames.json
echo "actual frames (ffprobe): $actual, extracted: $n"