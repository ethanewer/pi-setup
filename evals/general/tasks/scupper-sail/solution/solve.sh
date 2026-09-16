#!/bin/bash
# Oracle for scupper-sail. Installs the reference implementation of the
# responsive dashboard shell into /app: the stylesheet and the minimal HTML
# page, both authored from the spec in the instruction. The verifier then
# parses /app/styles.css with tinycss2 and resolves the cascade against the
# hidden viewport fixtures; this oracle simply supplies the real artifacts.
# It never reads /tests and never consults any precomputed expectation.
set -eu

cp /solution/styles.css /app/styles.css
cp /solution/dashboard.html /app/dashboard.html
chmod 644 /app/styles.css /app/dashboard.html

echo "oracle installed /app/styles.css and /app/dashboard.html"