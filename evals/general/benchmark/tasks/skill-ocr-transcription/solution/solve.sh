#!/bin/bash
# Oracle solution for skill-ocr-transcription.
set -euo pipefail

tesseract /app/quote.png stdout -l eng 2>/dev/null > /app/transcript.txt