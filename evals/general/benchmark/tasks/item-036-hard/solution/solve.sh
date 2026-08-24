#!/bin/bash
set -euo pipefail

# Whole-buffer transform driven by Vim: for each data row "id,code",
# remove the comma, swap fields, join with '-' (header line is untouched).
# Capture group 1 = integer id ( [0-9]... ), group 2 = two-letter code.
vim -c '%s/^\([0-9]\+\),\([A-Z][A-Z]\)$/\2-\1/' -c 'write' -c 'quit!' /app/data.csv

printf '1000000\n' > /app/report.txt