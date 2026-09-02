#!/bin/bash
# Oracle for cedar-vault: author the greedy generator, then RUN it on the
# shipped visible model to produce /app/greedy.json. Never reads /tests.
set -eu

cat > /app/generate.py <<'PY'
#!/usr/bin/env python3
"""Greedy continuation generator for Cedar Vault archive brains.

Greedy only: argmax score with ties broken to the lowest token id.
Temperature / top-k / top-p / repetition-penalty fields are ignored.
"""
import argparse
import json
import sys


def score_context(embed, head, toks):
    """score[i] = sum_{t in toks} sum_j embed[t][j] * head[j][i] (exact ints)."""
    V = len(head[0])
    sc = [0] * V
    for t in toks:
        row_e = embed[t]
        for j, e in enumerate(row_e):
            if e:
                hrow = head[j]
                for i in range(V):
                    sc[i] += e * hrow[i]
    return sc


def greedy(model, prompt):
    ctx = int(model["ctx"])
    max_new = int(model["max_new"])
    embed, head = model["embed"], model["head"]
    seq = [int(t) for t in prompt]
    cont = []
    for _ in range(max_new):
        toks = seq[-ctx:] if len(seq) >= ctx else seq
        sc = score_context(embed, head, toks)
        best = max(sc)
        seq.append(sc.index(best))  # index() -> lowest id on tie
        cont.append(seq[-1])
    return cont, seq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt", default=None)
    ap.add_argument("--out", default="/app/greedy.json")
    args = ap.parse_args()

    with open(args.model, "r", encoding="utf-8") as fh:
        model = json.load(fh)

    if args.prompt is not None:
        prompt = [int(x) for x in args.prompt.split(",") if x.strip() != ""]
    else:
        prompt = [int(t) for t in model["default_prompt"]]

    cont, full = greedy(model, prompt)
    out = {
        "prompt": prompt,
        "max_new": int(model["max_new"]),
        "continuation": cont,
        "full": full,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print("wrote", args.out)


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/generate.py

python3 /app/generate.py --model /app/model/lexicon.json --out /app/greedy.json

echo "solve.sh done"
ls -l /app/generate.py /app/greedy.json
