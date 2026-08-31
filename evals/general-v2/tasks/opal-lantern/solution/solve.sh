#!/bin/bash
# Oracle for opal-lantern: write the exporter program, then RUN it on the
# visible fixture to produce /app/exports/survey_fr.jsonl. Never reads /tests.
set -eu

SOLVER="/app/export_locale.py"
OUT="/app/exports/survey_fr.jsonl"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Locale-filter exporter for the Meridian Ornithology survey archive."""
import argparse
import json
import os


def resolve(rec, selector):
    cur = rec
    for part in selector.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return ""
    return cur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--locale", required=True)
    ap.add_argument("--columns", required=True,
                    help="comma-separated selectors, e.g. id,meta.site")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    selectors = [c.strip() for c in args.columns.split(",") if c.strip() != ""]

    out_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(out_dir, exist_ok=True)

    kept = []
    with open(args.input, "r", encoding="utf-8") as fh:
        for line in fh:
            stripped = line.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except (json.JSONDecodeError, ValueError):
                continue
            if not isinstance(obj, dict):
                continue
            if obj.get("locale") != args.locale:
                continue
            kept.append(obj)

    with open(args.output, "w", encoding="utf-8") as out:
        for rec in kept:
            row = {sel: resolve(rec, sel) for sel in selectors}
            out.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" --input /app/survey.jsonl --locale fr-FR \
  --columns record_id,meta.site,meta.banding.ring,species,count \
  --output "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
