#!/bin/bash
set -euo pipefail

mkdir -p /app/work/frames /app/app
ffmpeg -y -loglevel error -i /app/clip.mkv /app/work/frames/f_%03d.png

cat > /app/solve_023.py <<'PY'
import glob
import os
import sys

sys.path.insert(0, '/app')
from ocr.ocr import ocr as ocr_func

frames = sorted(glob.glob('/app/work/frames/f_*.png'),
                key=lambda p: int(os.path.basename(p).split('_')[-1].split('.')[0]))

unique = []
for fp in frames:
    t = ocr_func(fp).strip()
    if t and (not unique or unique[-1] != t):
        unique.append(t)

with open('/app/app/commands.txt', 'w') as f:
    f.write('\n'.join(unique) + ('\n' if unique else ''))
print(unique)
PY

python3 /app/solve_023.py