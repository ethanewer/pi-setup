#!/bin/bash
# Real oracle for copper-mesa: write the picker program (this IS the work)
# to /app/pick_top.py, then RUN it on the shipped visible dataset to
# produce /app/leaderboard_top.txt. Never reads /tests.
set -eu

cat > /app/pick_top.py <<'PYEOF'
#!/usr/bin/env python3
"""Reference implementation for copper-mesa.

Scan a sharded leaderboard results directory, compute each model's mean over
its numeric task scores, and write the top model's id as one trimmed line.
"""
import json
import math
import os
import sys


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def numeric(v):
    """True for finite int/float scores; bools and non-numbers excluded."""
    if isinstance(v, bool):
        return False
    if isinstance(v, (int, float)):
        return math.isfinite(v)
    return False


def collect(results_dir):
    """Return {model_id_trimmed: [scores]}."""
    scores = {}
    for entry in sorted(os.listdir(results_dir)):
        mdir = os.path.join(results_dir, entry)
        if not os.path.isdir(mdir):
            continue
        meta = load_json(os.path.join(mdir, "meta.json"))
        if not isinstance(meta, dict):
            continue
        model = meta.get("model")
        if not isinstance(model, str):
            continue
        model = model.strip()
        if not model:
            continue
        for fname in sorted(os.listdir(mdir)):
            if not fname.endswith(".json") or fname == "meta.json":
                continue
            shard = load_json(os.path.join(mdir, fname))
            if not isinstance(shard, dict):
                continue
            v = shard.get("score")
            if numeric(v):
                scores.setdefault(model, []).append(float(v))
    return scores


def top_model(scores):
    """Highest mean (rounded to 9 dp); ties -> lexicographically smallest id."""
    best_mean = None
    best_model = None
    for model, vals in scores.items():
        mean = round(sum(vals) / len(vals), 9)
        if (best_mean is None or mean > best_mean
                or (mean == best_mean and model < best_model)):
            best_mean, best_model = mean, model
    return best_model


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: pick_top.py <results_dir> <out_file>\n")
        return 2
    scores = collect(sys.argv[1])
    model = top_model(scores)
    if model is None:
        sys.stderr.write("ERR: no model with numeric scores found\n")
        return 1
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        fh.write(model + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

chmod +x /app/pick_top.py

python3 /app/pick_top.py /app/data/results /app/leaderboard_top.txt

echo "solve.sh done -> /app/pick_top.py and /app/leaderboard_top.txt"
cat /app/leaderboard_top.txt
