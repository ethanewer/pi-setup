#!/bin/bash
# Oracle solution for item-029-main.
# Scan the whole toolpath, keep only genuine printed segments (G1 + E token),
# floor the E value to a letter index, concatenate in file order, write answer.
set -euo pipefail

python3 - <<'EOF'
import re
ABC = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
out = []
with open("/app/job.gcode") as f:
    for line in f:
        if not re.match(r"\s*G1\b", line):
            continue  # metadata, homing, temperature, comments = not motion
        m = re.search(r"\bE([0-9]+(?:\.[0-9]*)?)", line)
        if m:
            out.append(ABC[int(float(m.group(1)))])  # floor(E) -> 0-based index
with open("/app/decoded.txt", "w") as f:
    f.write("".join(out))
EOF

echo DONE