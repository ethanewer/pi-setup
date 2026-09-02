#!/bin/bash
# Real oracle for quill-vane: transcribe the photographed functions into a
# working program, then RUN it on the shipped fixture to produce
# /app/answer.json. Never reads /tests.
set -eu

EVAL="/app/eval_funcs.py"
OUT="/app/answer.json"

cat > "$EVAL" <<'PY'
#!/usr/bin/env python3
"""Faithful transcriptions of the photographed snippets (func_a/func_b/func_c),
evaluated on probe arguments."""
import json
import sys


def func_a(n):
    acc = 7
    for k in range(3, 12, 2):
        acc = acc * 4 - k
    if acc % 3 == 0:
        acc = acc // 3
    return acc + 2 * n


def func_b(s):
    out = ""
    idx = 0
    while idx < len(s):
        ch = s[idx]
        if "a" <= ch <= "z":
            out = chr((ord(ch) - 97 + 11) % 26 + 97) + out
        else:
            out = out + ch
        idx = idx + 2
    return out


def func_c(xs):
    total = 0
    for i in range(len(xs)):
        v = xs[i]
        if v % 2 == 0:
            total = total + v * i
        else:
            total = total - v
    if total < 0:
        total = 0 - total
    return total % 1000


def main(argv):
    if len(argv) != 4:
        sys.stderr.write(
            "usage: eval_funcs.py <snippets_dir> <probe_json> <output_json>\n")
        return 2
    _snippets_dir, probe_path, out_path = argv[1], argv[2], argv[3]
    with open(probe_path, "r", encoding="utf-8") as fh:
        probe = json.load(fh)
    results = {
        "func_a": func_a(int(probe["func_a"])),
        "func_b": func_b(str(probe["func_b"])),
        "func_c": func_c(list(probe["func_c"])),
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
PY

chmod +x "$EVAL"

# Run the program on the shipped fixture to produce the deliverable output.
python3 "$EVAL" /app/snippets /app/probe.json "$OUT"

echo "solve.sh done -> $EVAL and $OUT"
cat "$OUT"
