#!/bin/bash
# Real oracle for mica-fjord: author the build_vocab.py program, then RUN it on
# the visible fixtures to produce /app/vocab.pkl and /app/vocab_report.json.
# Never reads /tests.
set -eu

SOLVER="/app/build_vocab.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import pickle
import re
import sys
from collections import Counter

import numpy as np

from station_vocab import Vocab


def main():
    if len(sys.argv) != 5:
        print("usage: build_vocab.py <corpus> <embeddings.npy> <out_pkl> <out_report>", file=sys.stderr)
        return 2
    corpus_path, emb_path, out_pkl, out_report = sys.argv[1:5]

    with open(corpus_path, "r", encoding="utf-8") as fh:
        text = fh.read()
    tokens = re.findall(r"[a-z0-9]+", text.lower())
    freq = Counter(tokens)
    candidates = sorted(
        (w for w, c in freq.items() if c >= 2), key=lambda w: (-freq[w], w)
    )

    emb = np.load(emb_path)
    rows = int(emb.shape[0])
    need = rows - 2
    if len(candidates) < need:
        print(
            "unsatisfiable: %d candidates with freq>=2 but %d regular slots needed"
            % (len(candidates), need),
            file=sys.stderr,
        )
        return 2

    regular = candidates[:need]
    word2idx = {"<pad>": 0, "<unk>": 1}
    for j, tok in enumerate(regular):
        word2idx[tok] = 2 + j
    idx2word = {i: w for w, i in word2idx.items()}

    vocab = Vocab(word2idx=word2idx, idx2word=idx2word)
    with open(out_pkl, "wb") as fh:
        pickle.dump(vocab, fh)

    report = {
        "vocab_size": vocab.size(),
        "embedding_rows": rows,
        "inverse_ok": bool(vocab.check_inverse()),
        "special_tokens": ["<pad>", "<unk>"],
        "first_regular": regular[0] if regular else None,
        "last_regular": regular[-1] if regular else None,
    }
    with open(out_report, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible fixtures.
cd /app
python3 "$SOLVER" /app/data/telemetry_corpus.txt /app/embeddings.npy \
    /app/vocab.pkl /app/vocab_report.json

echo "solve.sh done -> $SOLVER /app/vocab.pkl /app/vocab_report.json"
ls -l "$SOLVER" /app/vocab.pkl /app/vocab_report.json
