#!/bin/bash
# Real oracle for cinder-reach: write the solve.py program, then RUN it on the
# visible fixture to produce /app/stats.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/stats.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import math
import re
import sys

LINE_RE = re.compile(
    r'^(\S+) - (\S+) \[([^\]]+)\] '
    r'"([A-Z]+) (\S+) HTTP/\d+\.\d+" '
    r'([1-5]\d{2}) (\d+|-) (\d+) '
    r'"([^"]*)"$'
)


def percentile95(sorted_vals):
    n = len(sorted_vals)
    i = 0.95 * (n - 1)
    lo = math.floor(i)
    hi = math.ceil(i)
    if lo == hi:
        return float(sorted_vals[lo])
    frac = i - lo
    return sorted_vals[lo] + frac * (sorted_vals[hi] - sorted_vals[lo])


def main():
    in_path = sys.argv[1] if len(sys.argv) > 1 else "/app/access.log"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "/app/stats.json"

    total = 0
    malformed = 0
    classes = {"1xx": 0, "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
    latencies = []
    bytes_total = 0
    client_counts = {}

    with open(in_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if not line.strip():
                continue
            m = LINE_RE.match(line)
            if m is None:
                malformed += 1
                continue
            ip, _user, _ts, _method, _path, status, b, lat, _ref = m.groups()
            total += 1
            classes["%dxx" % (int(status) // 100)] += 1
            latencies.append(int(lat))
            bytes_total += 0 if b == "-" else int(b)
            client_counts[ip] = client_counts.get(ip, 0) + 1

    if total:
        error_rate = round((classes["4xx"] + classes["5xx"]) / total, 4)
        avg_latency = round(sum(latencies) / total, 4)
        p95 = round(percentile95(sorted(latencies)), 4)
        top_client = min(
            (-c, ip) for ip, c in client_counts.items()
        )[1]
    else:
        error_rate = None
        avg_latency = None
        p95 = None
        top_client = None

    report = {
        "total_requests": total,
        "malformed": malformed,
        "status_classes": classes,
        "error_rate": error_rate,
        "avg_latency_ms": avg_latency,
        "p95_latency_ms": p95,
        "bytes_total": bytes_total,
        "top_client": top_client,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$SOLVER" /app/access.log "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
