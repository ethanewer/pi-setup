#!/bin/bash
# Real oracle for opal-lexicon: writes the vocab_lib.py + build_vocab.py
# deliverables, then RUNS the builder on the visible corpus to produce the
# shipped artifacts. Never reads /tests.
set -eu

mkdir -p /app

# ---- 1. The vocabulary container module (required pickle module path).
cat > /app/vocab_lib.py <<'PY'
"""Opal lexicon vocabulary container."""
from dataclasses import dataclass
from typing import Dict, List


@dataclass
class Vocab:
    word2idx: Dict[str, int]
    idx2word: List[str]

    def size(self) -> int:
        return len(self.idx2word)

    def check_inverse(self) -> bool:
        if len(self.word2idx) != len(self.idx2word):
            return False
        if len(set(self.word2idx.values())) != len(self.word2idx):
            return False
        for token, idx in self.word2idx.items():
            if not isinstance(idx, int) or not (0 <= idx < len(self.idx2word)):
                return False
            if self.idx2word[idx] != token:
                return False
        return True
PY

# ---- 2. The reusable CLI builder.
cat > /app/build_vocab.py <<'PY'
#!/usr/bin/env python3
"""Deterministic glossary builder.

Usage: python3 build_vocab.py <corpus.txt> <out_dir>
Writes vocab.txt, embeddings.csv (16 floats per token row) and vocab.pkl
(a pickled vocab_lib.Vocab) into <out_dir>.
"""
import json
import os
import pickle
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vocab_lib import Vocab  # noqa: E402

DIM = 16


def token_frequencies(path):
    freq = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            for tok in line.split():
                freq[tok] = freq.get(tok, 0) + 1
    return freq


def build_vocab(path):
    freq = token_frequencies(path)
    order = sorted(freq, key=lambda t: (-freq[t], t))
    word2idx = {tok: i for i, tok in enumerate(order)}
    return Vocab(word2idx=word2idx, idx2word=order)


def embedding_row(token):
    rng = random.Random("glossary-v1:" + token)
    return [round(rng.gauss(0.0, 1.0), 6) for _ in range(DIM)]


def main():
    corpus_path, out_dir = sys.argv[1], sys.argv[2]
    vocab = build_vocab(corpus_path)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "vocab.txt"), "w", encoding="utf-8") as fh:
        for tok in vocab.idx2word:
            fh.write(tok + "\n")
    with open(os.path.join(out_dir, "embeddings.csv"), "w", encoding="utf-8") as fh:
        for tok in vocab.idx2word:
            fh.write(",".join(repr(x) for x in embedding_row(tok)) + "\n")
    with open(os.path.join(out_dir, "vocab.pkl"), "wb") as fh:
        pickle.dump(vocab, fh, protocol=4)
    print(json.dumps({"vocab_size": vocab.size()}))


if __name__ == "__main__":
    main()
PY

chmod +x /app/build_vocab.py

# ---- 3. Produce the shipped artifacts for the visible corpus.
python3 /app/build_vocab.py /app/data/corpus.txt /app

echo "solve.sh done"
ls -l /app/vocab_lib.py /app/build_vocab.py /app/vocab.txt /app/embeddings.csv /app/vocab.pkl
