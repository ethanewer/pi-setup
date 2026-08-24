#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-liberation
    mkdir -p /app
    # Create the video fixture with the required text visible around the 2-second mark
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='WARNING\: Do not leak the ELF section\: .hw_crypto_keys':fontcolor=white:fontsize=20:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1.5,3.5)'" -c:v libx264 -y /app/tutorial.mp4
rm -rf /home/user/.setup_tmp
