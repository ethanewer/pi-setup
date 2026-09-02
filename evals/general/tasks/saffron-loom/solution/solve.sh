#!/bin/bash
# Real oracle for saffron-loom: write the export program, then RUN it on the
# visible fixtures to produce /app/fr_export.jsonl. Never reads /tests.
set -eu

SOLVER="/app/export_lang.py"
OUT="/app/fr_export.jsonl"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Locale-filtered JSONL exporter for SaffronLoom catalogs."""
import argparse
import json


def load_rows(path):
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    if isinstance(doc, dict):
        doc = doc["records"]
    if not isinstance(doc, list):
        raise ValueError("dataset must be an array or {'records': [...]}")
    return [r for r in doc if isinstance(r, dict)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--query", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    with open(args.query, "r", encoding="utf-8") as fh:
        q = json.load(fh)
    locale = q["locale"]
    columns = list(q["columns"])

    kept = [r for r in load_rows(args.input)
            if isinstance(r.get("locale"), str) and r["locale"] == locale]

    with open(args.output, "w", encoding="utf-8") as fh:
        for row in kept:
            fh.write(json.dumps({c: row.get(c, "") for c in columns},
                                ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" --input /app/catalog.json --query /app/task.json --output "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
