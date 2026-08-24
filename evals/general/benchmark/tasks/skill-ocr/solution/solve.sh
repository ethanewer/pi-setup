#!/bin/bash
# Oracle solution for skill-ocr: run tesseract, keep first line, normalize.
set -euo pipefail

tesseract /app/ocr.png stdout -l eng 2>/dev/null | head -n 1 | tr -d ' \t\r' > /app/read.txt