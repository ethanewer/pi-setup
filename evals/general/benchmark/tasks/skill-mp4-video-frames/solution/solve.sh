#!/bin/bash
set -euo pipefail

cat > /app/frame.py <<'EOF'
import subprocess

subprocess.run(
    "ffmpeg -y -i /app/video.mp4 -ss 2.5 -frames:v 1 -f rawvideo -pix_fmt rgb24 -s 16x16 /app/frame.rgb".split(),
    check=True)

with open('/app/frame.rgb', 'rb') as f:
    raw = f.read()

n = 16 * 16
r = sum(raw[i*3+0] for i in range(n)) / n
g = sum(raw[i*3+1] for i in range(n)) / n
b = sum(raw[i*3+2] for i in range(n)) / n

with open('/app/report.txt', 'w') as f:
    f.write(f"{round(r)} {round(g)} {round(b)}\n")
EOF

python3 /app/frame.py