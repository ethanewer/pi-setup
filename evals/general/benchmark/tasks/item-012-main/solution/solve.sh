#!/bin/bash
# Oracle for item-012-main: implement the BRIEFCASE REDUCE algorithm in Python.
set -euo pipefail

cat > /app/briefcase.py <<'PY_EOF'
import sys

def reduce_line(line):
    acc = 0
    i = 0
    while i < len(line):
        ch = line[i]
        acc += ord(ch) - ord('a') + 1
        i += 1
    while acc >= 10:
        n = acc
        acc = 0
        while n > 0:
            acc += n % 10
            n //= 10
    return chr(48 + acc)

def main():
    with open("/app/input.txt", "r", newline="") as f:
        raw = f.read()
    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    out = []
    for ln in lines:
        if ln == "" or not any('a' <= c <= 'z' for c in ln):
            continue
        out.append(reduce_line(ln))
    with open("/app/output.txt", "w", newline="\n") as f:
        if out:
            f.write("\n".join(out) + "\n")

main()
PY_EOF

chmod +x /app/briefcase.py
# Self-check against the shipped sample (does not touch the harness contract).
cp /app/sample_input.txt /app/input.txt
python3 /app/briefcase.py
if ! cmp -s /app/sample_output.txt /app/output.txt; then
  echo "oracle self-check failed" >&2
  exit 1
fi
echo "oracle briefcase.py ready"