#!/bin/bash
set -euo pipefail
pdflatex -interaction=nonstopmode -output-directory=/app /app/report.tex
if [ ! -f /app/report.pdf ]; then
  echo "pdflatex did not produce report.pdf"
  exit 1
fi
echo "compiled /app/report.pdf"