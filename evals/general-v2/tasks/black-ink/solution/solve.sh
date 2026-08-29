#!/bin/bash
# Real oracle for black-ink: write the solve.py program, then RUN it on the
# visible fixtures to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import re
import sys
from datetime import date, datetime

RE_A = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) ([A-Z]+) ([A-Za-z0-9_]+) (\d+)ms$"
)
RE_B = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\] ([A-Z]+) ([A-Za-z0-9_]+) duration=(\d+)$"
)


def parse_line(raw):
    line = raw.rstrip("\n")
    m = RE_A.match(line)
    if m:
        ts, sev, op, ms = m.groups()
        return ts, sev, op, int(ms)
    m = RE_B.match(line)
    if m:
        ts, sev, op, ms = m.groups()
        return ts, sev, op, int(ms)
    return None


def load_query(path):
    bounds = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            key, _, value = line.partition("=")
            bounds[key.strip()] = value.strip()
    return date.fromisoformat(bounds["from"]), date.fromisoformat(bounds["to"])


def main():
    log_path, query_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    lo, hi = load_query(query_path)

    counts = {}
    total_ms = {}
    malformed = 0
    with open(log_path, "r", encoding="utf-8") as fh:
        for line in fh:
            parsed = parse_line(line)
            if parsed is None:
                malformed += 1
                continue
            ts, sev, op, ms = parsed
            dt = datetime.fromisoformat(ts).date()  # 'Z' supported by py3.11+
            if not (lo <= dt <= hi):
                continue
            key = "%s/%s" % (sev, op)
            counts[key] = counts.get(key, 0) + 1
            total_ms[key] = total_ms.get(key, 0) + ms

    average_ms = {key: total_ms[key] / counts[key] for key in counts}
    answer = {
        "average_ms": average_ms,
        "counts": counts,
        "malformed": malformed,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/operations.log /app/query.txt "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"