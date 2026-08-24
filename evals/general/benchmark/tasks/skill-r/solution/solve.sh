#!/bin/bash
set -euo pipefail
cat > /app/summarize.R <<'R'
d <- read.table("/app/stats.csv", header=TRUE, sep=",")
groups <- sort(unique(as.character(d$group)))
lines <- c("group,value")
for (g in groups) {
  sel <- d$value[d$group == g]
  m <- round(mean(sel), 2)
  lines <- c(lines, sprintf("%s,%.2f", g, m))
}
con <- paste(lines, collapse = "\n")
cat(con, file = "/app/summary.csv")
R
# run with whichever of Rscript/R exists; Rscript is standard on Ubuntu.
if command -v Rscript >/dev/null 2>&1; then
  Rscript /app/summarize.R
elif command -v R >/dev/null 2>&1; then
  R /app/summarize.R
else
  echo "no R interpreter found" >&2
fi
echo "wrote summary.csv"