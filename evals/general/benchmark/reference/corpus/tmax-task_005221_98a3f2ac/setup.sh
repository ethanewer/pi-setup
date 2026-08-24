#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip ffmpeg curl
    pip3 install --target /home/user/.local/lib/python3/dist-packages pytest opencv-python-headless numpy flask requests
    mkdir -p /app
    ffmpeg -f lavfi -i color=c=white:s=320x240:d=10 \
      -vf "drawbox=x=0:y=0:w=320:h=240:color=black:t=fill:enable='between(t,3,4)+between(t,8,9)'" \
      -r 1 -y /app/feed.mp4
rm -rf /home/user/.setup_tmp
