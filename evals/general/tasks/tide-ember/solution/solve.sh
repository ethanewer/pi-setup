#!/bin/bash
# Oracle for tide-ember: write the flux_select.py deliverable program, then RUN it
# on the visible fixtures to produce /app/ranked.json. Never reads /tests.
set -eu

SOLVER="/app/flux_select.py"
OUT="/app/ranked.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Calibrate, filter, and rank observations near a target flux value.

Usage: python3 flux_select.py <sources_dir> <units_json> <instruments_json>
                         <target_json> <output_json>
"""
import json
import math
import os
import sys


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def main():
    sources_dir, units_path, inst_path, target_path, out_path = sys.argv[1:6]
    with open(units_path, "r", encoding="utf-8") as fh:
        units = json.load(fh)
    with open(inst_path, "r", encoding="utf-8") as fh:
        instruments = json.load(fh)
    with open(target_path, "r", encoding="utf-8") as fh:
        target = json.load(fh)
    tval = float(target["value"])
    tol = float(target["tolerance"])

    kept = []
    for name in sorted(os.listdir(sources_dir)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(sources_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if not isinstance(data, list):
            continue
        for rec in data:
            if not isinstance(rec, dict):
                continue
            oid = rec.get("obs_id")
            inst = rec.get("instrument")
            fd = rec.get("flux_density")
            if not isinstance(oid, str) or not isinstance(inst, str):
                continue
            if not isinstance(fd, dict):
                continue
            cal = instruments.get(inst)
            if not isinstance(cal, dict):
                continue
            gain = cal.get("gain")
            if not is_num(gain):
                continue
            unit = fd.get("unit")
            raw = fd.get("value")
            if not isinstance(unit, str) or unit not in units:
                continue
            if not is_num(raw):
                continue
            factor = float(units[unit])
            gain = float(gain)
            value = round(float(raw) * factor * gain, 6)
            if not math.isfinite(value):
                continue
            distance = round(abs(value - tval), 4)
            if distance > tol:
                continue
            score = round(1.0 - distance / tol, 6)
            kept.append({
                "obs_id": oid,
                "instrument": inst,
                "value": value,
                "distance": distance,
                "score": score,
                "normalization": "%s->Jy x%r; gain %r" % (unit, factor, gain),
            })

    kept.sort(key=lambda e: (e["distance"], e["obs_id"]))
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(kept, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/sources /app/units.json /app/instruments.json \
    /app/target.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
