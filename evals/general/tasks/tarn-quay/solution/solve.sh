#!/bin/bash
# Oracle for tarn-quay: write the merge program, then RUN it on the visible
# snapshots to produce /app/merged.json. Never reads /tests.
set -eu

SOLVER="/app/merge.py"
OUT="/app/merged.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import csv
import json
import os
import sys


def normalize(rec):
    """Cast/strip one raw record; raises on malformed rows."""
    rid = int(str(rec["id"]).strip())
    name = str(rec["name"]).strip()
    value = int(str(rec["value"]).strip())
    return {"id": rid, "name": name, "value": value}


def rows_from_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            yield row


def rows_from_jsonl(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if isinstance(obj, dict):
                yield obj


def rows_from_json(path):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception:
        return
    if isinstance(data, dict):
        data = [data]
    if isinstance(data, list):
        for obj in data:
            if isinstance(obj, dict):
                yield obj


def merge(snapshots_dir):
    best = {}
    for fn in sorted(os.listdir(snapshots_dir)):
        path = os.path.join(snapshots_dir, fn)
        if not os.path.isfile(path):
            continue
        if fn.endswith(".csv"):
            gen = rows_from_csv(path)
        elif fn.endswith(".jsonl"):
            gen = rows_from_jsonl(path)
        elif fn.endswith(".json"):
            gen = rows_from_json(path)
        else:
            continue
        for rec in gen:
            try:
                n = normalize(rec)
            except Exception:
                continue
            k = (n["value"], n["name"])
            if n["id"] not in best or k < (best[n["id"]]["value"], best[n["id"]]["name"]):
                best[n["id"]] = n
    return [best[i] for i in sorted(best)]


def main():
    snapshots_dir, out_path = sys.argv[1], sys.argv[2]
    merged = merge(snapshots_dir)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(merged, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible snapshots to generate the output.
python3 "$SOLVER" /app/snapshots "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
