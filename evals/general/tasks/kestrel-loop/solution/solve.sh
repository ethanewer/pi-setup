#!/bin/bash
# Real oracle for kestrel-loop: write the spec_loop.py program, then RUN it on
# the shipped visible case (args parsed from /app/spec_case.txt) to produce
# /app/spec_result.json. Never reads /tests.
set -eu

SOLVER="/app/spec_loop.py"
OUT="/app/spec_result.json"

# ---- 1. Write the deliverable program (this IS the work).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Speculative draft-and-verify loop over a dual-logits model."""
import argparse
import json


def parse_ids(text):
    text = (text or "").strip()
    if not text:
        return []
    return [int(x) for x in text.split(",") if x.strip() != ""]


def load_model(path):
    with open(path, "r", encoding="utf-8") as fh:
        m = json.load(fh)
    V = int(m["vocab_size"])
    draft = m["draft_logits"]
    if len(draft) != V or any(len(row) != V for plane in draft for row in plane):
        raise ValueError("draft_logits shape mismatch")
    return V, draft


def argmax_lowest(scores):
    """Index of the maximum score, ties broken to the LOWEST index."""
    best = 0
    for i in range(1, len(scores)):
        if scores[i] > scores[best]:
            best = i
    return best


def spec_loop(V, draft, prefix, target, K):
    def draft_next(a, b):
        return argmax_lowest(draft[a][b])

    ctx = list(prefix)
    base = len(prefix)
    n_drafted = n_accepted = n_corrected = 0
    blocks = []
    while len(ctx) < base + len(target):
        start = len(ctx)
        tmp = list(ctx)
        block = []
        for _ in range(K):
            t = draft_next(tmp[-2], tmp[-1])
            block.append(t)
            tmp.append(t)
        n_drafted += K
        pos = start - base
        remaining = len(target) - pos
        accepted = 0
        rejected = False
        for j in range(min(K, remaining)):
            if block[j] == target[pos + j]:
                accepted += 1
            else:
                rejected = True
                break
        blocks.append({
            "start": start,
            "draft": list(block),
            "accepted": accepted,
            "rejected": rejected,
        })
        ctx.extend(block[:accepted])
        if rejected:
            ctx.append(target[pos + accepted])
            n_corrected += 1
        n_accepted += accepted
    return {
        "vocab_size": V,
        "prefix": list(prefix),
        "target": list(target),
        "draft_len": K,
        "result": ctx,
        "n_drafted": n_drafted,
        "n_accepted": n_accepted,
        "n_corrected": n_corrected,
        "blocks": blocks,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--draft", type=int, required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    prefix = parse_ids(args.prefix)
    target = parse_ids(args.target)
    if len(prefix) < 2:
        raise SystemExit("prefix must have at least 2 token ids")
    if args.draft < 1:
        raise SystemExit("draft block length K must be >= 1")

    V, draft = load_model(args.model)
    result = spec_loop(V, draft, prefix, target, args.draft)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# ---- 2. Run the produced program on the shipped visible case to generate the
#         visible deliverable /app/spec_result.json.
CASE="/app/spec_case.txt"
MODEL="$(sed -n 's/^model=//p' "$CASE")"
PREFIX="$(sed -n 's/^prefix=//p' "$CASE")"
DRAFT="$(sed -n 's/^draft=//p' "$CASE")"
TARGET="$(sed -n 's/^target=//p' "$CASE")"

python3 "$SOLVER" --model "$MODEL" --prefix "$PREFIX" --target "$TARGET" \
  --draft "$DRAFT" --out "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
