#!/bin/bash
# Real oracle for elm-anchor: writes the BPE learner (/app/emit.py) and runs it
# on the visible corpus to produce /app/vocab.txt and /app/merges.txt. Never
# reads /tests. Optional args (authoring-time expected generation):
#   bash solve.sh <corpus> <outdir>
set -eu

CORPUS="${1:-/app/data/corpus.txt}"
OUTDIR="${2:-/app}"

SOLVER="/app/emit.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Learn BPE merges from a corpus and emit Merm-loader-format files."""
import os
import sys


def learn(words):
    """words: dict word -> freq. Returns (vocab_list, merges_list)."""
    freqs = {}
    for w, f in words.items():
        freqs[tuple(w)] = f
    base = sorted({ch for w in words for ch in w})
    vocab = list(base)
    merges = []

    def count_pairs(sym_freqs):
        counts = {}
        for syms, f in sym_freqs.items():
            for i in range(len(syms) - 1):
                pair = (syms[i], syms[i + 1])
                counts[pair] = counts.get(pair, 0) + f
        return counts

    def apply_merge(sym_freqs, pair):
        a, b = pair
        merged = a + b
        out = {}
        for syms, f in sym_freqs.items():
            new = []
            i = 0
            while i < len(syms):
                if i < len(syms) - 1 and syms[i] == a and syms[i + 1] == b:
                    new.append(merged)
                    i += 2
                else:
                    new.append(syms[i])
                    i += 1
            out[tuple(new)] = out.get(tuple(new), 0) + f
        return out

    while len(merges) < 300:
        counts = count_pairs(freqs)
        if not counts:
            break
        best_count = max(counts.values())
        if best_count < 2:
            break
        # highest count; ties -> lexicographically smallest (left, right)
        best_pair = min(p for p, c in counts.items() if c == best_count)
        merges.append(best_pair)
        vocab.append(best_pair[0] + best_pair[1])
        freqs = apply_merge(freqs, best_pair)
    return vocab, merges


def main(corpus_path, outdir):
    with open(corpus_path, "r", encoding="utf-8") as fh:
        words = {}
        for w in fh.read().split():
            words[w] = words.get(w, 0) + 1

    vocab, merges = learn(words)

    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "vocab.txt"), "w", encoding="utf-8") as fh:
        for t in vocab:
            fh.write(t + "\n")
    with open(os.path.join(outdir, "merges.txt"), "w", encoding="utf-8") as fh:
        for a, b in merges:
            fh.write("%s %s\n" % (a, b))
    print("EMIT_OK vocab=%d merges=%d" % (len(vocab), len(merges)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: emit.py <corpus.txt> <outdir>\n")
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced learner on the requested corpus -------------------
python3 "$SOLVER" "$CORPUS" "$OUTDIR"

echo "solve.sh done -> $SOLVER, $OUTDIR/vocab.txt, $OUTDIR/merges.txt"
ls -l "$SOLVER" "$OUTDIR/vocab.txt" "$OUTDIR/merges.txt"
