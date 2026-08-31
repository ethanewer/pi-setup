#!/usr/bin/env bash
# larch-vane stage 2: reduce a staging directory into the JSON deployment
# report. usage: enrich.sh <staging-dir> <report-json>
set -euo pipefail
export LC_ALL=C

if [ "$#" -ne 2 ]; then
  echo "usage: enrich.sh <staging-dir> <report-json>" >&2
  exit 2
fi

SRC="$1"
OUT="$2"

python3 - "$SRC" "$OUT" <<'PY'
import glob, json, os, re, sys

src, out = sys.argv[1], sys.argv[2]
station_re = re.compile(r"[A-Za-z0-9_-]+\Z")
int_re = re.compile(r"-?[0-9]+\Z")

entries = []
total = 0
for path in sorted(glob.glob(os.path.join(src, "*.log"))):
    readings = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split(",")
            if len(parts) != 3:
                continue
            st, dep, bat = (p.strip() for p in parts)
            if not station_re.fullmatch(st):
                continue
            if not int_re.fullmatch(dep) or not int_re.fullmatch(bat):
                continue
            readings.append((st, int(dep), int(bat)))
    total += len(readings)
    entries.append({
        "file": os.path.basename(path),
        "readings": len(readings),
        "depth_min": min(d for _, d, _ in readings) if readings else None,
        "depth_max": max(d for _, d, _ in readings) if readings else None,
        "battery_low": min(b for _, _, b in readings) if readings else None,
        "first_station": readings[0][0] if readings else None,
    })

report = {"files": entries, "total_readings": total}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
PY
