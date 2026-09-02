#!/bin/bash
# Real oracle for hazel-quarry: write the lexicon builder, then RUN it on the
# visible fixtures to produce /app/lexicon.txt. Never reads /tests.
set -eu

SOLVER="/app/lexicon.py"
OUT="/app/lexicon.txt"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Frequency-filtered vocabulary builder for the Hazel Quarry archive."""
import argparse
import re
from pathlib import Path

TOKEN_RE = re.compile(r"\w+")


def tokenize(text):
    return TOKEN_RE.findall(text.lower())


def load_required(path):
    terms = set()
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        term = line.strip().lower()
        if term:
            terms.add(term)
    return terms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", action="append", required=True)
    ap.add_argument("--required", required=True)
    ap.add_argument("--min-count", type=int, required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    counts = {}
    for corpus in args.corpus:
        for token in tokenize(Path(corpus).read_text(encoding="utf-8")):
            counts[token] = counts.get(token, 0) + 1

    protected = load_required(args.required)
    kept = {t for t, c in counts.items() if c >= args.min_count} | protected
    lines = sorted(kept)
    Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" \
    --corpus /app/data/corpus_aria.txt --corpus /app/data/corpus_borealis.txt \
    --required /app/data/required_terms.txt --min-count 4 --out "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
wc -l "$OUT"
