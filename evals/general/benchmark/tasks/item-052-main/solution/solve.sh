#!/bin/bash
set -euo pipefail

# Add the single missing \end{enumerate} line right before \end{document}.
# This is the one targeted correction required by the defect.
(
  while IFS= read -r line; do
    if [ "$line" = '\end{document}' ]; then
      echo '\end{enumerate}'
    fi
    echo "$line"
  done < /app/report.tex
) > /app/report.tex.new
mv /app/report.tex.new /app/report.tex

cd /app
pdflatex -interaction=nonstopmode report.tex
pdflatex -interaction=nonstopmode report.tex