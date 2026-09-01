#!/bin/bash
# Real oracle for cobalt-fjord: write the solve.py program, then RUN it on the
# visible fixture to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import re
import sys

RE_A = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) (\S+) ([A-Z]+) (\S+) (\d{3}) (\d+|-) (\d+)ms$"
)


def parse_line(raw):
    line = raw.rstrip("\n")
    m = RE_A.match(line)
    if m:
        ts, client, method, path, status, nbytes, lat = m.groups()
        status = int(status)
        if not (100 <= status <= 599):
            return None
        return (client, method, path, status,
                0 if nbytes == "-" else int(nbytes), int(lat))
    parts = line.split("|")
    if len(parts) == 7:
        ts, client, method, path, status, nbytes, lat = (p.strip() for p in parts)
        if (
            re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", ts)
            and client and not re.search(r"\s", client)
            and re.fullmatch(r"[A-Z]+", method)
            and path and not re.search(r"\s", path)
            and re.fullmatch(r"\d{3}", status) and 100 <= int(status) <= 599
            and (nbytes == "-" or re.fullmatch(r"\d+", nbytes))
            and re.fullmatch(r"\d+", lat)
        ):
            return (client, method, path, int(status),
                    0 if nbytes == "-" else int(nbytes), int(lat))
    return None


def main():
    log_path, out_path = sys.argv[1], sys.argv[2]
    total = 0
    malformed = 0
    classes = {"1xx": 0, "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0}
    lat_sum = 0
    lats = []
    bytes_total = 0
    clients = set()
    ep_count = {}
    ep_ms = {}
    with open(log_path, "r", encoding="utf-8") as fh:
        for line in fh:
            rec = parse_line(line)
            if rec is None:
                malformed += 1
                continue
            client, method, path, status, nbytes, lat = rec
            total += 1
            classes["%dxx" % (status // 100)] += 1
            lat_sum += lat
            lats.append(lat)
            bytes_total += nbytes
            clients.add(client)
            ep_count[path] = ep_count.get(path, 0) + 1
            ep_ms[path] = ep_ms.get(path, 0) + lat

    error_rate = None
    avg = None
    p95 = None
    health = "unknown"
    if total:
        rate = round(100.0 * (classes["4xx"] + classes["5xx"]) / total, 2)
        error_rate = rate
        avg = lat_sum / total
        s = sorted(lats)
        rank = 0.95 * (len(s) - 1)
        lo = int(rank)
        hi = min(lo + 1, len(s) - 1)
        p95 = s[lo] + (rank - lo) * (s[hi] - s[lo])
        health = ("healthy" if rate < 5.0
                  else "degraded" if rate < 15.0 else "critical")

    answer = {
        "total_requests": total,
        "malformed": malformed,
        "status_classes": classes,
        "error_rate_pct": error_rate,
        "avg_latency_ms": avg,
        "p95_latency_ms": p95,
        "bytes_total": bytes_total,
        "unique_clients": len(clients),
        "endpoints": {
            p: {"count": ep_count[p], "avg_ms": ep_ms[p] / ep_count[p]}
            for p in ep_count
        },
        "health": health,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$SOLVER" /app/access.log "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
