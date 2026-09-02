#!/usr/bin/env python3
"""Saffron-rune deterministic hashed-token SMILES featurizer (reference impl)."""
import csv
import sys

import numpy as np

VEC_DIM = 96

ALLOWED = set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789()[]+=#%@/.$-"
)


def _zero():
    return np.zeros(VEC_DIM, dtype=np.float32)


def featurize_one(smiles):
    if not isinstance(smiles, str):
        return _zero()
    s = smiles.strip()
    if not s:
        return _zero()
    for ch in s:
        if ch not in ALLOWED:
            return _zero()
    tokens = []
    i = 0
    n = len(s)
    while i < n:
        if s[i] == "[":
            j = s.find("]", i + 1)
            if j == -1:
                return _zero()
            tokens.append(s[i:j + 1])
            i = j + 1
        elif s[i:i + 2] in ("Cl", "Br"):
            tokens.append(s[i:i + 2])
            i += 2
        else:
            tokens.append(s[i])
            i += 1
    x = np.zeros(VEC_DIM, dtype=np.float64)
    for pos, tok in enumerate(tokens):
        tid = 0
        for ch in tok:
            tid = (tid * 131 + ord(ch)) % 1000003
        x[(pos * 31 + tid) % VEC_DIM] += 1.0
    return x.astype(np.float32)


def featurize_column(smiles_list):
    return [featurize_one(s) for s in smiles_list]


def main():
    rows = []
    with open("/app/molecules.csv", newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            rows.append(row)
    vecs = featurize_column([r["smiles"] for r in rows])
    ids = [r["id"] for r in rows]
    X = np.stack(vecs).astype(np.float32)
    np.savez("/app/features.npz", X=X, ids=np.array(ids))
    print("wrote /app/features.npz", X.shape, X.dtype)
    return 0


if __name__ == "__main__":
    sys.exit(main())
