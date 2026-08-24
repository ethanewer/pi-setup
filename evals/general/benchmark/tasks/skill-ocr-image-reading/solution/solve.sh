#!/bin/bash
# Oracle solution for skill-ocr-image-reading.
set -euo pipefail

tesseract /app/badge.png stdout -l eng 2>/dev/null \
  | grep -oE 'ID[[:space:]]*[0-9]{4}' \
  | head -n 1 \
  | tr -cd '0-9' > /app/id.txt