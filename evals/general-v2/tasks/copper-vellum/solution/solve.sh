#!/bin/bash
# Oracle for copper-vellum: writes the deliverable program (embodying the
# transcription of the photographed routine), then RUNS it on the shipped
# fixture to produce /app/answer.json. Does real work; never reads /tests.
set -eu

PROGRAM="/app/routine.py"
OUT="/app/answer.json"

cat > "$PROGRAM" <<'PY'
#!/usr/bin/env python3
"""Copper-vellum deliverable.

Evaluates the routine transcribed from the photograph /app/routine.png
(berthq batch control, legacy build 3) plus the documented auxiliary chain
in its unguarded ("samples") and guarded ("trace") variants.

Usage: python3 routine.py <input_json> <output_json>
"""
import json
import sys


def photographed_run(a, b):
    # Transcribed exactly from /app/routine.png.
    base = a * 17
    alt = b ^ 3
    if base > alt:
        base = base - alt
    else:
        base = base + 2 * alt
    mid = base // 2
    return mid % 1009


def chain(a, b, guarded):
    v1 = a * 2
    v2 = b ^ 33
    v3 = v1 + v2
    v4 = v1 | v3
    if guarded:
        if v3 > 37:
            v4 = v4 ^ 26
        else:
            v4 = v4 + 37
    v5 = v4 >> 2
    return {"v1": v1, "v2": v2, "v3": v3, "v4": v4, "v5": v5}


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: routine.py <input_json> <output_json>")
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    a = int(spec["a"])
    b = int(spec["b"])
    answer = {
        "truth_id": photographed_run(a, b),
        "samples": chain(a, b, guarded=False),
        "trace": chain(a, b, guarded=True),
    }
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2, sort_keys=True)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$PROGRAM"

python3 "$PROGRAM" /app/input.json "$OUT"

echo "solve.sh done -> $PROGRAM and $OUT"
ls -l "$PROGRAM" "$OUT"
