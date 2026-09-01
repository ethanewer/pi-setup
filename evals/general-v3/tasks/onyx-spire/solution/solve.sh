#!/bin/bash
# Oracle for onyx-spire: write the export_rows.py deliverable program, then RUN
# it on the visible fixtures to produce /app/answer.jsonl. Never reads /tests.
set -eu

SOLVER="/app/export_rows.py"
OUT="/app/answer.jsonl"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Filter a JSONL dataset to one locale and export the requested columns.

Usage: python3 export_rows.py <dataset_jsonl> <job_file> <output_jsonl>
"""
import json
import sys


def load_job(path):
    spec = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            key, _, value = line.partition("=")
            spec[key.strip()] = value.strip()
    locale = spec["locale"]
    columns = [c.strip() for c in spec["columns"].split(",") if c.strip() != ""]
    return locale, columns


def main():
    dataset_path, job_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    locale, columns = load_job(job_path)

    kept = []
    with open(dataset_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            if not isinstance(rec, dict):
                continue
            if rec.get("locale") != locale:
                continue
            kept.append({col: rec.get(col, None) for col in columns})

    with open(out_path, "w", encoding="utf-8") as fh:
        for rec in kept:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/manifest.jsonl /app/job.txt "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
